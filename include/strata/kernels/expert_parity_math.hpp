// include/strata/kernels/expert_parity_math.hpp
// Deterministic host/device arithmetic for --expert-parity cuda.
// The purpose is not to approximate CUDA fast-math on the CPU.  Instead both CPU and CUDA parity paths use this
// exact sequence of round-to-f32 operations, so expert placement does not change the arithmetic contract.
#pragma once

#include <cstdint>
#include <cstring>

#if defined(__CUDACC__) || defined(__HIPCC__)
#define STRATA_PARITY_HD __host__ __device__ __forceinline__
#else
#define STRATA_PARITY_HD inline
#endif

namespace strata::kernels {

STRATA_PARITY_HD float parity_add_rn(float a, float b) {
#if defined(__CUDA_ARCH__)
    return __fadd_rn(a, b);
#elif defined(__HIP_DEVICE_COMPILE__)
    return a + b;
#else
    volatile float v = a + b;
    return v;
#endif
}

STRATA_PARITY_HD float parity_mul_rn(float a, float b) {
#if defined(__CUDA_ARCH__)
    return __fmul_rn(a, b);
#elif defined(__HIP_DEVICE_COMPILE__)
    return a * b;
#else
    volatile float v = a * b;
    return v;
#endif
}

STRATA_PARITY_HD float parity_div_rn(float a, float b) {
#if defined(__CUDA_ARCH__)
    return __fdiv_rn(a, b);
#elif defined(__HIP_DEVICE_COMPILE__)
    return a / b;
#else
    volatile float v = a / b;
    return v;
#endif
}

// A shared f32 exp approximation.  Range reduction keeps r in about [-ln(2)/2, ln(2)/2], where a 7th-order
// Taylor polynomial is accurate to better than ~2e-8 absolute before f32 rounding.  The operations are written
// one by one so host and CUDA follow the same rounding sequence.  Parity mode is opt-in; the normal fast path
// continues to use the engine's existing exp implementation.
STRATA_PARITY_HD float parity_exp_f32(float x) {
    if (x > 80.0f) x = 80.0f;
    if (x < -80.0f) x = -80.0f;
    constexpr float LOG2E = 1.44269504088896341f;
    constexpr float LN2_HI = 0.69314575195312500f;
    constexpr float LN2_LO = 1.42860676533018705e-6f;
    const float z = parity_mul_rn(x, LOG2E);
    const int n = (int) parity_add_rn(z, z >= 0.0f ? 0.5f : -0.5f);
    float r = parity_add_rn(x, -parity_mul_rn((float) n, LN2_HI));
    r = parity_add_rn(r, -parity_mul_rn((float) n, LN2_LO));

    // Horner form of 1 + r + r^2/2! + ... + r^7/7!.
    float p = 1.9841269841269841e-4f;   // 1/5040
    p = parity_add_rn(1.3888888888888889e-3f, parity_mul_rn(r, p));   // 1/720
    p = parity_add_rn(8.3333333333333332e-3f, parity_mul_rn(r, p));   // 1/120
    p = parity_add_rn(4.1666666666666664e-2f, parity_mul_rn(r, p));   // 1/24
    p = parity_add_rn(1.6666666666666666e-1f, parity_mul_rn(r, p));   // 1/6
    p = parity_add_rn(5.0000000000000000e-1f, parity_mul_rn(r, p));   // 1/2
    p = parity_add_rn(1.0000000000000000f, parity_mul_rn(r, p));
    p = parity_add_rn(1.0000000000000000f, parity_mul_rn(r, p));

    if (n > 127) return 3.402823466e38f;
    if (n < -126) return 0.0f;
    const uint32_t bits = (uint32_t) (n + 127) << 23;
    union { uint32_t u; float f; } cvt;
    cvt.u = bits;
    const float two_n = cvt.f;
    return parity_mul_rn(p, two_n);
}

STRATA_PARITY_HD float parity_silu_mul(float gate, float up) {
    if (gate >= 20.0f) return parity_mul_rn(gate, up);
    if (gate <= -20.0f) return parity_mul_rn(parity_mul_rn(gate, parity_exp_f32(gate)), up);
    const float e = parity_exp_f32(-gate);
    const float den = parity_add_rn(1.0f, e);
    return parity_mul_rn(parity_div_rn(gate, den), up);
}

}  // namespace strata::kernels

#undef STRATA_PARITY_HD
