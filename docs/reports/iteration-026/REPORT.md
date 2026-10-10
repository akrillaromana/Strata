# Strata Custom 0.1.39, iteration 026 — finite Q8_1 SwiGLU and safe CUDA indexing

**Input:** full 025 archive, user-confirmed GitHub HEAD `02ec8ec` on `strata-v0.1.39-custom`.

## Real numerical errors fixed

1. `src/kernels/cuda/native_mmvq.cu::native_swiglu_quantize_q8_1_kernel`: unlike the normal `native_quantize_q8_1` path, fused SwiGLU used a raw `amax/127` and `make_half2(d,sum)` without the existing finite-half clamp. Finite activations such as 32×3000 produce sum=96000, encoded as FP16 infinity, making subsequent Q6_K/Q8_0 dot products vulnerable to NaN. Fused SwiGLU now calls `q8_1_finite`, `q8_1_quant` and `q8_1_ds` exactly as the separate quantizer does. This also saturates int8 values when FP16 d has to be clamped.
2. `src/kernels/cuda/iq_kernels.cu`: the grouped expert multi-token fused gate/up → SwiGLU → Q8_1 path had the same unbounded FP16 fields and a separate int8 rule. Now it reuses **`q8_1_store`**, the existing 32-lane quantizer shared by the other grouped paths, preserving the entry/row stride.
3. `src/kernels/cuda/native_mmvq.cu::validate_shape`: while `n_in` was positive and `ncols` bounded by 8, `n_in*ncols` could overflow `int` before computing grid size and indexed Q8_1 activation buffers. New host/CUDA-compatible shape predicate in `include/strata/kernels/native_mmvq_shape.hpp` rejects the overflow **before any CUDA launch**. It preserves ordinary valid dimensions and all existing type-specific block constraints.
4. `src/kernels/iq_multi_parity.cpp`: adds the fused SwiGLU path to the existing synthetic GPU parity fixture with ordinary, sum-overflow and scale-overflow cases. This is **not executed** here without CUDA SDK/GPU; it is a regression ready for a future permitted GPU build.

Normal blocks keep their Q8_1 behavior; for extreme finite values, saturated FP16 scale/sum and int8 quantization are an intentional correction, not bit-exact agreement with the previous defective fused implementation. NaN input remains outside the finite-input contract.

## Boundaries

This does **not** mean all Q6_K/Unsloth Q8_0/Huihui Q8_0 paths, original model PLE, all RCO IQ3_S, MTP/shared topology, vision, or JSON Schema constrained token decoding are completed. No CUDA/HIP compilation or real GGUF inference was performed, and the owner’s E:/R: installations and personal profiles remain untouched.
