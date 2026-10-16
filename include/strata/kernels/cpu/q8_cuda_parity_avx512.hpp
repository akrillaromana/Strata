#pragma once

#include <cstdint>

namespace strata::kernels::cpu {

// Exact integer part of CUDA's four 8-value Q8_0 dot calls for one 32-value block.
// The caller must dispatch here only when cpu_avx512_base_ok() is true.
void q8_cuda_parity_dot4_avx512(const int8_t* w, const int8_t* x, int out[4]) noexcept;

}  // namespace strata::kernels::cpu
