# Remaining code tasks after 029

- [x] Guard IQ3_S/Q6_K/Q8_0 grouped MMVQ dimensions and output indexing before launch.
- [x] Remove signed overflow from native expert eligibility and guard grouped expert offsets and scratch arithmetic.
- [x] Guard Q8_1 row quantizer signed multiplication and invalid row geometry.
- [x] Reject unsupported grouped MMVQ type without `std::exit(1)`.
- [ ] Audit and fix other hard-exit sites in CUDA/HIP/experts so recoverable per-request issues cannot terminate server.
- [ ] Finish opt-in Q6_K expert + prefill compute paths for actual five Unsloth GGUF shards; verify numeric kernels (not completed).
- [ ] Verify Unsloth and Huihui six-shard Q8_0 with original Q8_0 PLE/n-gram *without* IQ4_NL substitution.
- [ ] Inspect and support the exact three GSQ-RCO IQ3_S tensor layouts, pruned-expert counts and tokenizer metadata.
- [ ] Inspect four real BF16/Q8_0 MTP/shared GGUFs and verify native draft numerical semantics.
- [ ] Implement complete mmproj Vision and native token-level JSON Schema constrained decoding, finish relevant donor 0.1.41 features.
- [ ] Complete QSA host pinned memory and teardown audit.
- [ ] On explicit request ONLY: real CUDA/HIP build, parity benchmark, on-device per-model execution. None undertaken here.

Do not change personal Windows BAT/PS1/JSON, data/personal_models.json, user installed runtime, model weights, E:/R: paths or unrelated Git untracked files.
