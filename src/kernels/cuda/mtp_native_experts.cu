// Strata personal MTP: native BF16/Q8_0 routed experts, WITHOUT Q2_0 conversion.
// Exact stored weight values are used. This is a correctness-first GEMV path;
// no assumption about the machine's model files or CUDA architecture.
#include "strata/kernels/mtp_native_experts.hpp"
#include "strata/kernels/mtp_native_launch_shape.hpp"
#include <cuda_fp16.h>
#include <cuda_runtime.h>
#include <cmath>
#include <cstdint>

namespace strata::kernels {
namespace {
constexpr int THREADS = 128;

__device__ __forceinline__ float weight_at(const uint8_t* row, int col, int kind) {
    if (kind == 8) {
        const uint8_t* b = row + (size_t) (col / 32) * 34;
        // ggml Q8_0: 16-bit IEEE FP16 scale, 32 signed int8 values.
        const unsigned short scale = (unsigned short) b[0] | ((unsigned short) b[1] << 8);
        return __half2float(__ushort_as_half(scale)) * (float) (int8_t) b[2 + col % 32];
    }
    // ggml BF16: 16-bit little-endian bit pattern, NOT IEEE half.
    const uint8_t* b = row + (size_t) col * 2;
    const uint32_t bits = ((uint32_t) b[0] | ((uint32_t) b[1] << 8)) << 16;
    return __uint_as_float(bits);
}

__global__ void gate_up_kernel(const uint8_t* base, const int32_t* ids, const float* x,
                               float* output, int hits, int k, int count, int h, int ff,
                               int kind, uint64_t stride) {
    const int row = (int) blockIdx.x;
    const int hit = (int) blockIdx.y;
    if (hit >= hits || row >= 2 * ff) return;
    const int id = ids[hit];
    if (id < 0 || id >= count) {
        if (threadIdx.x == 0) output[(size_t) hit * 2 * ff + row] = 0.0f;
        return;
    }
    const uint64_t row_bytes = kind == 8 ? (uint64_t) h / 32 * 34 : (uint64_t) h * 2;
    const uint8_t* row_weights = base + (uint64_t) id * stride + (uint64_t) row * row_bytes;
    const float* input = x + (size_t) (hit / k) * h;
    float partial = 0.f;
    for (int col = threadIdx.x; col < h; col += blockDim.x)
        partial += weight_at(row_weights, col, kind) * input[col];
    __shared__ float sums[THREADS];
    sums[threadIdx.x] = partial;
    __syncthreads();
    for (int gap = THREADS / 2; gap != 0; gap >>= 1) {
        if (threadIdx.x < gap) sums[threadIdx.x] += sums[threadIdx.x + gap];
        __syncthreads();
    }
    if (threadIdx.x == 0) output[(size_t) hit * 2 * ff + row] = sums[0];
}

__global__ void swiglu_kernel(const float* gu, float* mid, int hits, int ff) {
    const size_t i = (size_t) blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= (size_t) hits * ff) return;
    const int hit = (int) (i / ff), row = (int) (i % ff);
    const float gate = gu[(size_t) hit * 2 * ff + row];
    const float up = gu[(size_t) hit * 2 * ff + ff + row];
    mid[i] = (gate / (1.0f + expf(-gate))) * up;
}

__global__ void down_kernel(const uint8_t* base, const int32_t* ids, const float* mid,
                            float* output, int hits, int count, int h, int ff, int kind,
                            uint64_t gate_bytes, uint64_t stride) {
    const int row = (int) blockIdx.x, hit = (int) blockIdx.y;
    if (hit >= hits || row >= h) return;
    const int id = ids[hit];
    if (id < 0 || id >= count) {
        if (threadIdx.x == 0) output[(size_t) hit * h + row] = 0.0f;
        return;
    }
    const uint64_t row_bytes = kind == 8 ? (uint64_t) ff / 32 * 34 : (uint64_t) ff * 2;
    const uint8_t* row_weights = base + (uint64_t) id * stride + gate_bytes + (uint64_t) row * row_bytes;
    const float* input = mid + (size_t) hit * ff;
    float partial = 0.f;
    for (int col = threadIdx.x; col < ff; col += blockDim.x)
        partial += weight_at(row_weights, col, kind) * input[col];
    __shared__ float sums[THREADS];
    sums[threadIdx.x] = partial;
    __syncthreads();
    for (int gap = THREADS / 2; gap != 0; gap >>= 1) {
        if (threadIdx.x < gap) sums[threadIdx.x] += sums[threadIdx.x + gap];
        __syncthreads();
    }
    if (threadIdx.x == 0) output[(size_t) hit * h + row] = sums[0];
}
} // namespace

void mtp_native_experts(const uint8_t* experts, const int32_t* ids, const float* x,
                        float* scratch, float* output, int hits, int k, int n_expert,
                        int h, int ff, int gate_kind, int down_kind,
                        uint64_t gate_bytes, uint64_t expert_bytes, cudaStream_t stream) {
    if (!experts || !ids || !x || !scratch || !output ||
        !mtp_native_launch_shape(hits, k, n_expert, h, ff, gate_kind, down_kind)) return;
    // CUDA graph capture safe: only launches using caller-owned persistent buffers.
    float* const gu = scratch;
    float* const mid = scratch + (size_t) hits * 2 * ff;
    gate_up_kernel<<<dim3((unsigned) (2 * ff), (unsigned) hits), THREADS, 0, stream>>>(
        experts, ids, x, gu, hits, k, n_expert, h, ff, gate_kind, expert_bytes);
    swiglu_kernel<<<(hits * ff + 255) / 256, 256, 0, stream>>>(gu, mid, hits, ff);
    down_kernel<<<dim3((unsigned) h, (unsigned) hits), THREADS, 0, stream>>>(
        experts, ids, mid, output, hits, n_expert, h, ff, down_kind, gate_bytes, expert_bytes);
}
} // namespace strata::kernels
