# Strata Custom v0.1.39 — Iteration 025

**Scope: fix all reproducible failures and the import error in the unfiltered tool regression suite left by iteration 024.** The latest user-confirmed published HEAD is `477090b` (024).

The formerly failing broad test run (515 tests, 48 failures, one import error, one skip) now completes with **523 tests, zero failures, zero errors, two explicit skips**. The additional tests verify source-level resource lifetimes.

- `tools/test_setup_golden.py`: fix cross-platform executable-name normalization which inadvertently rewrote `strata-*` log names; covers normal and CUDA-12 engine paths. No change to generated run settings.
- `tools/test_setup_amd.py`: make Windows HIP archive test platform-independent by simulating the Windows executable and Windows platform (not the host's Linux name).
- `tools/test_setup_pins.py`: account for `jsonschema` and four newly required dependencies on legacy stamp-based installations. Preserve the actual requirement installation semantics instead of pretending new dependencies aren't needed.
- `tools/test_iq_pack.py`: missing optional llama.cpp `gguf-py` is **reported as a skipped integration test** instead of aborting discovery via `SystemExit`; not counted as a pass.
- `setup.py`: close both `/proc/cpuinfo` files deterministically; tolerate a missing `flags` field.
- `tools/canonical_xcheck.py`: close the GGUF source file descriptor immediately after a successful or failed `mmap` creation. The returned mapping remains owned by its caller.
- `tools/test_source_fd_lifecycle.py`: 7 new regression cases for CPU flag parsing and successful/failed GGUF mapping ownership.

**Verification:** 523 tool tests (521 run, two skips), 32 server tests, 8 personal-profile tests, 55 JS tests, 7 independent C++ tests with `-Werror`, Python syntax compilation. No CUDA build, installed engine changes, user GGUF weights, real-model test, or changes to personal paths.

Full root `CONTINUE_PROMPT.md` and iteration-025 reports give the exact state. The whole project and eight individual model paths are **not** proven end-to-end ready. Remaining tasks include Q6_K/Q8_0 CUDA math, original Q8 PLE, real MTP/shared topologies, three RCO IQ3_S, mmproj vision, native token-constrained JSON and select 0.1.41 upstream capabilities.
