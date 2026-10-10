# Remaining code tasks after 024

- [x] Fix partial NativeEmbed state and pinned alias failures for both CUDA/HIP; transactional release on any copy/alloc failure, CPU mock lifetime tests.
- [ ] Complete Unsloth Q6_K opt-in grouped/dense CUDA expert math, MMQ prompt path and benchmark/parity integration.
- [ ] Complete Huihui and Unsloth Q8_0 original PLE and native n-gram end-to-end.
- [ ] Confirm exact routed/shared MTP BF16/Q8_0 GGUF tensor layouts and finish non-quantized shared-only topology support.
- [ ] Validate full native IQ3_S paths on all three user RCO variants, including special expert pruning and full output path.
- [ ] Complete mmproj/vision source functionality; token-level constrained JSON Schema/Anthropic endpoints; outstanding relevant 0.1.41 donor integrations.
- [ ] Validate full engine build and real-model outputs when explicitly authorized by the user (not executed in this source-only iteration).

Source code is not yet 100% complete. Do not use test pass counts as end-to-end GPU/model proof.
