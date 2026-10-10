// Iteration 026: CPU-only boundary/shape checks; CUDA execution is separate.
#include "strata/kernels/native_mmvq_shape.hpp"
#include "strata/kernels/f16_bits.hpp"
#include <algorithm>
#include <array>
#include <stdexcept>
#define CHECK(c) do { if (!(c)) throw std::runtime_error("Q8_1 test failure: " #c); } while (false)
#include <cmath>
#include <cstdint>
#include <limits>

namespace k = strata::kernels;

// Host reference of finite Q8_1 scale and sum used by native and grouped
// SwiGLU quantizers. Independent of the GPU implementation under test.
struct Encoded { uint16_t scale, sum; std::array<int8_t, 32> q; };
Encoded encode(const std::array<float, 32>& a) {
    float maximum = 0.f, sum = 0.f;
    for (float x : a) { maximum = std::max(maximum, std::fabs(x)); sum += x; }
    auto finite = [](float x) { return std::fabs(x) > 65504.f ? std::copysign(65504.f, x) : x; };
    const float d = finite(maximum / 127.f);
    Encoded result{};
    result.scale = k::f16_from_f32(d);
    result.sum = k::f16_from_f32(finite(sum));
    for (size_t i = 0; i < a.size(); ++i) {
        const float q = maximum == 0.f ? 0.f : std::round(a[i] / d);
        result.q[i] = (int8_t)std::clamp(q, -127.f, 127.f);
    }
    return result;
}
void finite_block(const std::array<float, 32>& x) {
    const Encoded b = encode(x);
    CHECK(std::isfinite(k::f32_from_f16(b.scale)));
    CHECK(std::isfinite(k::f32_from_f16(b.sum)));
    for (int8_t q : b.q) CHECK(q >= -127 && q <= 127);
}
int main() {
    static_assert(k::native_mmvq_shape_ok(2560, 8, 256));
    static_assert(k::native_mmvq_shape_ok(268435424, 8, 32));
    static_assert(!k::native_mmvq_shape_ok(268435456, 8, 32));
    static_assert(!k::native_mmvq_shape_ok(2147483616, 2, 32));
    static_assert(!k::native_mmvq_shape_ok(0, 1, 32));
    static_assert(!k::native_mmvq_shape_ok(255, 1, 256));
    static_assert(!k::native_mmvq_shape_ok(256, 0, 256));
    static_assert(!k::native_mmvq_shape_ok(256, 9, 256));
    static_assert(!k::native_mmvq_shape_ok(256, 1, 0));
    std::array<float,32> zero{};
    auto z = encode(zero);
    CHECK(z.scale == 0 && z.sum == 0);
    for (auto q : z.q) CHECK(q == 0);

    // Ordinary values: clamp must be inert and quantizer unchanged.
    std::array<float,32> ordinary{};
    for (int i=0;i<32;++i) ordinary[i] = float(i-16) * 0.25f;
    auto o = encode(ordinary);
    float amax = 4.f, sum = 0.f;
    for (auto x : ordinary) sum += x;
    CHECK(o.scale == k::f16_from_f32(amax / 127.f));
    CHECK(o.sum == k::f16_from_f32(sum));
    finite_block(ordinary);

    // 32 finite activations overflowing Q8_1 FP16 sum in original fused path.
    std::array<float,32> high{};
    high.fill(3000.f);
    CHECK(!std::isfinite(k::f32_from_f16(k::f16_from_f32(96000.f))));
    auto h = encode(high);
    CHECK(k::f32_from_f16(h.sum) == 65504.f);
    finite_block(high);
    high.fill(-3000.f);
    CHECK(k::f32_from_f16(encode(high).sum) == -65504.f);
    finite_block(high);

    // One very large finite activation overflows the FP16 scale; the
    // old fused quantizer stored inf while the shared path saturates.
    high.fill(0.5f);
    high[3] = -20000000.f;
    CHECK(!std::isfinite(k::f32_from_f16(k::f16_from_f32(20000000.f/127.f))));
    h = encode(high);
    CHECK(k::f32_from_f16(h.scale) == 65504.f);
    CHECK(h.q[3] == -127);
    finite_block(high);

    // CPU transcription of the fused gate/up path: with gate=50 the sigmoid
    // multiplier rounds to one, so its activation is 50*(value/50).
    // Both ordinary and overflowing blocks must obey the same Q8_1 contract.
    for (const auto& target : {ordinary, high}) {
        std::array<float, 32> swiglu{};
        for (size_t i = 0; i < 32; ++i) {
            const float gate = 50.f;
            swiglu[i] = (gate / (1.f + std::exp(-gate))) * (target[i] / gate);
        }
        finite_block(swiglu);
        const auto q = encode(swiglu);
        for (int8_t v : q.q) CHECK(v >= -127 && v <= 127);
    }
}
