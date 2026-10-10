# Remaining source-code work after 013

- [x] User's Q8 profile no longer points to unrelated IQ4_NL n-gram.
- [x] Native loader rejects non-Q8 PLE and missing original PLE (in Q8 mode).
- [x] GGUF split preflight and Q8 geometry validation, including truncation.
- [x] Resolve Git trailing EOF blank lines introduced in 012 PS1 launchers.
- [ ] Verify real Q8_0 tensor headers when owner later supplies original model; no model weights included in repository.
- [ ] Complete end-to-end Q8_0 model path (CPU/CUDA experts, native prefill/grouped/MTP) and Huihui Q8_0 with all GGUF shard variants and model metadata.
- [ ] Complete Q6_K end-to-end and cross-layer compatibility with donor 0.1.41.
- [ ] Token-constrained Structured Output (JSON Schema) and Anthropic API support.
- [ ] Remaining donor 0.1.41 improvements: VMM, DMA, persistence, speculative paths, CUDA/CPU/SYCL with careful per-module integration.
- [ ] Real user hardware tests (only after separate owner request; not a code-completion percentage criterion).
