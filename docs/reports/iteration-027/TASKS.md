# Open code tasks after iteration 027

- [x] Restore global KV modes on all MTP draft KV init early exits and exceptions.
- [x] Release pinned host allocation on failure to obtain its CUDA alias, before publishing pointers.
- [x] Avoid dangling/double-free KV arena pointer on draft resident fallback failure.
- [x] Reject duplicate/partial MTP object initialization and CUDA device-query failure.
- [x] Reject malformed native BF16/Q8_0 MTP `hits / top-k` groupings and integer-overflow launches.
- [ ] Audit QSA state-wide pinned staging/KV host pool lifetime in `qsa_state_init` and session/MTP teardown; not solved by mapped() changes here.
- [ ] Complete native Q6_K expert + prefill + MMQ end-to-end for all five Unsloth shards; compiled opt-in route is not proof.
- [ ] Complete native Q8_0 own PLE/n-gram end-to-end for both six-shard Unsloth/Huihui variants, without IQ4_NL substitution.
- [ ] Support and verify all three GSQ-RCO IQ3_S variants using their exact GGUF tensors and layouts.
- [ ] Validate exact primary and shared MTP BF16/Q8_0 tensor topology, numerical CUDA draft parity and real standalone/shared MTP files.
- [ ] Finish mmproj/vision and native token-level constrained JSON Schema decoding.
- [ ] Integrate remaining compatible donor 0.1.41 components selectively (VMM/DMA, file conversation storage, speculative controls, backend paths).
- [ ] Repeat the unfiltered 523-case tools suite; iteration 027's 101 profile-specific tests are not a full-suite pass.
- [ ] CUDA/HIP hardware build and model execution only when the owner explicitly authorizes testing.

Personal BAT/PS1/JSON and paths on E:/R: remain untouched. Not a complete fork or all-model green light.
