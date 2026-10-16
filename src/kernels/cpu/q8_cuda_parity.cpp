#include "strata/kernels/cpu/q8_cuda_parity.hpp"
#include "strata/kernels/cpu/q8_cuda_parity_avx512.hpp"
#include "strata/kernels/cpu/expert_layout.hpp"
#include "strata/kernels/expert_parity_math.hpp"
#include "strata/kernels/f16_bits.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace strata::kernels::cpu {
namespace {

struct Q81 {
    uint16_t d;
    uint16_t s;
    int8_t q[32];
};
static_assert(sizeof(Q81) == 36, "Q8_1 parity layout");

float finite_half_input(float v) {
    constexpr float hm = 65504.0f;
    return std::fabs(v) > hm ? std::copysign(hm, v) : v;
}

void quant_block(const float* x, Q81& b) {
    float lane_max[32], lane_sum[32];
    for (int i = 0; i < 32; ++i) {
        lane_max[i] = std::fabs(x[i]);
        lane_sum[i] = x[i];
    }
    // CUDA q8_1_store's warp xor butterfly.  Each round reads the previous round's values simultaneously.
    for (int off = 16; off > 0; off >>= 1) {
        float old_m[32], old_s[32];
        std::memcpy(old_m, lane_max, sizeof old_m);
        std::memcpy(old_s, lane_sum, sizeof old_s);
        for (int i = 0; i < 32; ++i) {
            lane_max[i] = std::max(old_m[i], old_m[i ^ off]);
            lane_sum[i] = parity_add_rn(old_s[i], old_s[i ^ off]);
        }
    }
    const float amax = lane_max[0];
    float d = finite_half_input(parity_div_rn(amax, 127.0f));
    b.d = f16_from_f32(d);
    b.s = f16_from_f32(finite_half_input(lane_sum[0]));
    for (int i = 0; i < 32; ++i) {
        if (amax == 0.0f) { b.q[i] = 0; continue; }
        // CUDA roundf: half away from zero.  The quotient is an explicitly rounded f32 operation.
        const float qf = parity_div_rn(x[i], d);
        const float aq = std::fabs(qf);
        int qi = (int) std::floor(aq + 0.5f);
        if (qf < 0.0f) qi = -qi;
        qi = std::max(-127, std::min(127, qi));
        b.q[i] = (int8_t) qi;
    }
}

inline int dot8(const int8_t* a, const int8_t* b) {
    int s = 0;
    for (int i = 0; i < 8; ++i) s += (int) a[i] * (int) b[i];
    return s;
}

// Reproduce iq_kernels.cu row_dot<Q8_0>: 32 logical warp lanes, four 8-value calls per Q8_0 block, lane-strided
// accumulation followed by the xor reduction tree.  This is deliberately not collapsed into one scalar dot: the
// floating-point accumulation order is the contract we are trying to match.
float row_dot_q8_cuda(const uint8_t* row, const Q81* x, int n_values) {
    const int nb = n_values / 32;
    float lane[32] = {};
    const bool avx512 = cpu_avx512_base_ok();
    for (int block = 0; block < nb; ++block) {
        const uint8_t* wb = row + (size_t) block * 34;
        uint16_t wd_bits;
        std::memcpy(&wd_bits, wb, 2);
        const float wd = f32_from_f16(wd_bits);
        const Q81& xb = x[block];
        const float xd = f32_from_f16(xb.d);
        int sums[4];
        if (avx512) {
            q8_cuda_parity_dot4_avx512((const int8_t*) wb + 2, xb.q, sums);
        } else {
            for (int part = 0; part < 4; ++part)
                sums[part] = dot8((const int8_t*) wb + 2 + part * 8, xb.q + part * 8);
        }
        const float scale = parity_mul_rn(wd, xd);
        for (int part = 0; part < 4; ++part) {
            const int k = block * 4 + part;
            const int l = k & 31;
            const float term = parity_mul_rn(scale, (float) sums[part]);
            lane[l] = parity_add_rn(lane[l], term);
        }
    }
    for (int off = 16; off > 0; off >>= 1) {
        float old[32];
        std::memcpy(old, lane, sizeof old);
        for (int i = 0; i < 32; ++i) lane[i] = parity_add_rn(old[i], old[i ^ off]);
    }
    return lane[0];
}

}  // namespace

size_t q8_cuda_parity_act_bytes(int64_t n) noexcept {
    return n > 0 && n % 32 == 0 ? (size_t) (n / 32) * sizeof(Q81) : 0;
}

void q8_cuda_parity_quant(const float* x, int64_t n, void* dst) {
    Q81* out = (Q81*) dst;
    for (int64_t b = 0; b < n / 32; ++b) quant_block(x + b * 32, out[b]);
}

void q8_cuda_parity_gu_rows(const uint8_t* blob, size_t gu_row, size_t up_off, int64_t n_embd,
                            const void* const* act, int nt, float* const* ff, int r0, int r1) {
    for (int r = r0; r < r1; ++r) {
        const uint8_t* gr = blob + (size_t) r * gu_row;
        const uint8_t* ur = blob + up_off + (size_t) r * gu_row;
        for (int t = 0; t < nt; ++t) {
            const Q81* a = (const Q81*) act[t];
            const float g = row_dot_q8_cuda(gr, a, (int) n_embd);
            const float u = row_dot_q8_cuda(ur, a, (int) n_embd);
            ff[t][r] = parity_silu_mul(g, u);
        }
    }
}

void q8_cuda_parity_down_rows(const uint8_t* blob, size_t down_off, size_t d_row, int64_t n_ff,
                              const void* const* hq, int nt, float* const* out, int r0, int r1) {
    for (int r = r0; r < r1; ++r) {
        const uint8_t* dr = blob + down_off + (size_t) r * d_row;
        for (int t = 0; t < nt; ++t)
            out[t][r] = row_dot_q8_cuda(dr, (const Q81*) hq[t], (int) n_ff);
    }
}

}  // namespace strata::kernels::cpu
