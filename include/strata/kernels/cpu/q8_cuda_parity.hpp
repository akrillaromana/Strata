#pragma once

#include <cstddef>
#include <cstdint>

namespace strata::kernels::cpu {

// CUDA's native expert path uses block_q8_1 activations even for Q8_0 weights.  These helpers reproduce that
// contract on the CPU for --expert-parity cuda.  The buffer layout is exactly 36 bytes per 32 values.
size_t q8_cuda_parity_act_bytes(int64_t n) noexcept;
void q8_cuda_parity_quant(const float* x, int64_t n, void* dst);
void q8_cuda_parity_gu_rows(const uint8_t* blob, size_t gu_row, size_t up_off, int64_t n_embd,
                            const void* const* act, int nt, float* const* ff, int r0, int r1);
void q8_cuda_parity_down_rows(const uint8_t* blob, size_t down_off, size_t d_row, int64_t n_ff,
                              const void* const* hq, int nt, float* const* out, int r0, int r1);

}  // namespace strata::kernels::cpu
