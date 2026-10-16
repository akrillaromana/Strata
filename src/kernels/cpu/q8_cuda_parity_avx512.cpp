#include "strata/kernels/cpu/q8_cuda_parity_avx512.hpp"

#include <immintrin.h>

namespace strata::kernels::cpu {

void q8_cuda_parity_dot4_avx512(const int8_t* w, const int8_t* x, int out[4]) noexcept {
    // Products fit in signed int16: (-127..127)^2.  We deliberately keep the four CUDA 8-value calls
    // separate at the reduction boundary.  AVX-512 only accelerates the exact integer multiplies; the
    // f32 scale/accumulate order remains in q8_cuda_parity.cpp and therefore matches the CUDA contract.
    const __m256i wb = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(w));
    const __m256i xb = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(x));
    const __m512i w16 = _mm512_cvtepi8_epi16(wb);
    const __m512i x16 = _mm512_cvtepi8_epi16(xb);
    const __m512i p16 = _mm512_mullo_epi16(w16, x16);
    alignas(64) int16_t p[32];
    _mm512_store_si512(reinterpret_cast<__m512i*>(p), p16);

    for (int part = 0; part < 4; ++part) {
        int s = 0;
        const int base = part * 8;
        for (int i = 0; i < 8; ++i) s += (int) p[base + i];
        out[part] = s;
    }
}

}  // namespace strata::kernels::cpu
