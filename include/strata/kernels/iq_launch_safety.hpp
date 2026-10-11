#pragma once
// Pure C++ geometry and allocation contract shared by CUDA/HIP IQ3_S/Q6_K/Q8_0
// kernels and grouped expert setup. No CUDA runtime is needed to test this.
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace strata::kernels {

constexpr bool iq_mmvq_shape_ok(int n_in, int n_out, int ncols, int block_elems) noexcept {
    return block_elems > 0 && n_in > 0 && n_out > 0 &&
           ncols >= 1 && ncols <= 8 && (n_in % block_elems) == 0 &&
           n_in <= (std::numeric_limits<int>::max)() / ncols &&
           n_out <= (std::numeric_limits<int>::max)() / ncols &&
           n_out <= (std::numeric_limits<int>::max)() - 3;
}

// A zero-row quantization is deliberately a no-op, but malformed row widths are
// not. The GPU grid uses a 32-bit block count and the quantizer indexes n values.
constexpr bool iq_quantize_rows_shape_ok(int64_t rows, int64_t cols) noexcept {
    return rows >= 0 && cols > 0 && cols % 32 == 0 &&
           cols <= (std::numeric_limits<int>::max)() &&
           rows <= (std::numeric_limits<int>::max)() / cols;
}

inline size_t iq_safe_mul(size_t a, size_t b) {
    if (a && b > (std::numeric_limits<size_t>::max)() / a)
        throw std::length_error("native grouped expert: allocation size overflow");
    return a * b;
}
inline size_t iq_safe_add(size_t a, size_t b) {
    if (b > (std::numeric_limits<size_t>::max)() - a)
        throw std::length_error("native grouped expert: allocation size overflow");
    return a + b;
}
inline size_t iq_align_256(size_t n) { return iq_safe_add(n, 255) & ~size_t(255); }

struct IqExpertOffsets {
    size_t up = 0, down = 0, total = 0;
};
inline IqExpertOffsets iq_expert_offsets(size_t gate_row_bytes, size_t down_row_bytes,
                                          int64_t n_embd, int64_t n_ff) {
    if (!gate_row_bytes || !down_row_bytes || n_embd <= 0 || n_ff <= 0 ||
        n_embd > (std::numeric_limits<int>::max)() || n_ff > (std::numeric_limits<int>::max)())
        throw std::invalid_argument("native grouped expert: invalid matrix geometry");
    const size_t up = iq_safe_mul(size_t(n_ff), gate_row_bytes);
    const size_t down = iq_safe_mul(up, 2);
    return {up, down, iq_safe_add(down, iq_safe_mul(size_t(n_embd), down_row_bytes))};
}
inline size_t iq_expert_scratch_bytes_checked(int64_t cap, int64_t n_ff) {
    if (cap <= 0 || n_ff <= 0 || n_ff % 32 != 0 ||
        cap > (std::numeric_limits<int>::max)() || n_ff > (std::numeric_limits<int>::max)())
        throw std::invalid_argument("native grouped expert: invalid scratch geometry");
    const size_t entries = iq_safe_mul(size_t(cap), size_t(n_ff));
    const size_t f = iq_align_256(iq_safe_mul(entries, sizeof(float)));
    const size_t q = iq_align_256(iq_safe_mul(entries / 32, size_t(36)));
    return iq_safe_add(iq_safe_mul(f, 3), q);
}
} // namespace strata::kernels
