# Iteration 025: verified fixes and remaining work

## Completed this iteration

- [x] 46 golden-config failures: normalize executable name only in real engine binary paths, including CUDA-12; retain original log filenames.
- [x] One Windows HIP fixture failure: target platform made explicit.
- [x] One legacy pip pin fixture failure: newly required JSON Schema stack installed when absent, existing installed stack kept.
- [x] One optional gguf-py import error: clearly flagged dependency skip, not hidden as success.
- [x] Fix Linux CPU probe unclosed handles and `flags` missing crash.
- [x] Fix `open_shard()` leaked Python file descriptor around mmap.
- [x] Seven new resource-lifetime regression tests, full Python/JS and seven CPU C++ programs.

## Still open

- [ ] Install `gguf-py` in an isolated tool environment and actually run optional `test_iq_pack` (not a prerequisite for source-only package delivery; don't touch owner's PC).
- [ ] Complete and verify native Unsloth Q6_K expert CUDA/MMQ and prefill route.
- [ ] Complete Q8_0 PLE/n-gram end-to-end without IQ4_NL substitution, Huihui Q8_0 and Unsloth Q8_0.
- [ ] Verify all three personal GSQ-RCO IQ3_S alternatives and real MTP BF16/Q8_0/shared tensor topologies.
- [ ] Finish mmproj/vision, token-level constrained JSON Schema, selected non-conflicting donor 0.1.41 functionality.
- [ ] Actual Windows/CUDA/HIP build and real-model tests only when user explicitly authorizes.

Do not mark the source base, target model coverage, or the whole project 100%. Do not change personal E:/R: profiles or GGUF model files.
