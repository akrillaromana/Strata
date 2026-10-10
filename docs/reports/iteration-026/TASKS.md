# Open tasks after 026

- [x] Fix the two divergent fused SwiGLU Q8_1 quantizers: finite FP16 scale/sum and saturated int8; keep normal-block behavior.
- [x] Reject overflow in `n_in*ncols` before native MMVQ CUDA activation launches.
- [x] Provide a CPU-only regression for the numeric edge cases and a GPU fixture for later execution.
- [ ] Build and actually execute `iq_multi_parity` including SwiGLU on supported CUDA/HIP hardware **only after owner explicitly requests hardware testing**.
- [ ] Finish native Q6_K expert/prefill/MMQ end-to-end and verify proper selection for five Unsloth shards.
- [ ] Finish original native Unsloth/Huihui Q8_0 PLE/n-gram and numerically verify both six-shard model variants.
- [ ] Complete exact GSQ-RCO IQ3_S variants and real MTP BF16/Q8_0/shared model topologies, without mixing GGUF variants.
- [ ] Complete mmproj/vision and true token-level JSON Schema-constrained decoding.
- [ ] Continue selected upstream 0.1.41 integrations without wholesale replacement of fork sources, personal profiles or installation.
- [ ] Optionally repeat the 523-case unfiltered tools suite with a longer mock-tuning timeout; 026's targeted tests are green, **not** a fresh 523-case pass.

No 100% general project claim. Do not instruct the user to build or run their models or modify `E:`/`R:` as part of source-only iterations.
