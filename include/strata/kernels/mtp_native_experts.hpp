#pragma once
#include <cuda_runtime.h>
#include <cstdint>
namespace strata::kernels {
// Strictly lossless expert-storage compute: Q8_0 blocks or BF16 bit patterns.
// Input: x[T,H], expert ids[T*K], output: y[T*K,H], scratch[3*T*K*FF].
// No CPU staging, heap allocation or memcpy during graph capture.
void mtp_native_experts(const uint8_t* experts, const int32_t* ids, const float* x,
                        float* scratch, float* output, int hits, int k, int n_expert,
                        int h, int ff, int gate_kind, int down_kind,
                        uint64_t gate_bytes, uint64_t expert_bytes, cudaStream_t stream);
}
