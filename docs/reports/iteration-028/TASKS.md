# Remaining code tasks after 028

- [x] Reject an apparently valid Q8_0 PLE source if other native GGUF tensors/shards fail the common payload/split audit.
- [x] Validate CUDA/SYCL PLE prefill batch grid bounds, scratch buffers and weights before any GPU kernels; accept proper 2-byte-aligned F16 conv weights.
- [ ] Verify full CUDA/HIP/SYCL build and numerical PLE batch parity (NOT undertaken in source-only phase).
- [ ] Complete native Q6_K expert & prefill runtime for all five Unsloth shards, not just GGUF structure and optional kernels.
- [ ] Verify original Q8_0 PLE/n-gram end-to-end for six-shard Unsloth and Huihui without lossy table substitution.
- [ ] Inspect and support exact three GSQ-RCO IQ3_S model tensor layouts and quantized runtime.
- [ ] Validate exact four BF16/Q8_0 MTP/shared GGUF topologies and native GPU draft numerical parity.
- [ ] Complete mmproj vision support and token-level constrained JSON Schema sampling.
- [ ] Selectively integrate donor 0.1.41 functionality without replacing customized kernels or engine wholesale.
- [ ] Audit QSA state-wide pinned host pools and teardown; add model-specific negative CUDA tests when authorized.
- [ ] Only when explicitly requested: build/test installed GPU engine on owner hardware and real model shards.

Personal profiles and paths on E:/R: must not be mutated. Preserve clean staged path whitelist and both unrelated untracked files in user's Git repository.
