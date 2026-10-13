# 013 — Native Q8_0 n-gram / PLE source

- `strata-unsloth-q8_0.json`: removed `--ple-gguf R:\q8-ple\...IQ4_NL.gguf`; added `--ple-require-type Q8_0`, preserved all other arguments and E:/R: paths.
- `src/program/generate.cpp`: native GGUF split auto-discovery finds original `per_layer_token_embd.weight`, requires type `Q8_0`, dimensions `[160, 320001536]`, validated payload boundaries. Checks type again after `PleTable::open`. Missing/wrong quantization fails explicitly rather than starting a different model.
- `src/ngram/ple_reader.cpp`: integer-overflow-safe bounds for direct Q8_0 row reader.
- `tools/q8_ple_preflight.py`: offline header-only diagnostic for original Q8_0 split; missing shards, geometry mismatch and truncated payload cause failure. Does not read model tensor values or perform inference.
- `tools/test_q8_ple_preflight.py`: synthetic/sparse GGUF fixtures for right/wrong/missing/truncated table and original Q8 configuration.
- `tools/windows/q4-local-profiles/test_personal_profiles.py`: removed outdated acceptance of mixed Q8+IQ4 PLE. Mirrored personal profile and docs in `PERSONAL_START_E_ai_Strata-Q4-Fork`.
- 4 PS1 copies (Q4/Huihui scripts in both folders): removed extra empty line at end that blocked `git diff --cached --check` for iteration 012. No runtime logic changed.

## Not verified

No real Q8_0 GGUF/PLE tensor was supplied, and the owner's existing E: binary has not been rebuilt or run. Actual execution of full model, CUDA and RAM staging remain outside the current phase. If the supplied GGUF itself contains an IQ4_NL table, **the tool rejects it**; an original Q8_0 GGUF containing its own table is required. Header presence alone is insufficient to claim inference correctness.

## Internal checks completed in this iteration

- Q8 sparse synthetic GGUF preflight: 8/8 checks (right type, wrong type, missing PLE, missing shard, wrong shape, truncation, owner JSON and code enforcement).
- Personal profiles: 8/8 checks (including identical mirrored copies, saved E:/R: paths and preserved sampling).
- JavaScript UI/API regression: 55/55.
- Python Structured Output/System Prompts/Prometheus regression: 29/29.
- CPU C++ native Q8_0 block dequantization (170-byte row): passed.
- `src/ngram/ple_reader.cpp` strict host compiler syntax check: passed.
- Git staged content against 011, `core.whitespace=cr-at-eol diff --cached --check`: passed; 53 changed paths, no deletions.

**Not performed:** complete CUDA engine compilation or Windows model execution. No real Q8 GGUF source or native table content is available in this task.
