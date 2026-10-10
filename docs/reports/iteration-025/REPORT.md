# Strata Custom v0.1.39 — iteration 025 delivery report

**Base:** complete iteration 024 archive, user-confirmed GitHub commit `477090b` on `strata-v0.1.39-custom`.

**Objective:** re-run broad failed tests from 024, fix their causes without weakening production behavior, then find and fix real source defects.

**Results:** tools unfiltered regression was 515 tests, 48 fail + 1 error + 1 skip. After the fixes: 523 tests, no errors, no failures, two explicitly documented dependency/platform skips. For details, `TEST_FAILURES.md`. 32 server tests, 8 personal profile tests, 55 JS tests and 7 standalone C++ tests also pass.

**Product improvements:** deterministic resource ownership on Linux CPU information reads, safe parsing of absent flags fields, and closing GGUF file descriptors after establishing read-only memory maps. These defects weren't papered over by changing test baselines.

**Test fixes:** golden normalization modified only for expected executable path, Windows HIP fixture explicitly uses Windows binary and simulated platform, and legacy requirements tests recognize JSON Schema dependencies; missing optional `gguf-py` becomes a visible skipped integration test, not an import crash. No golden baseline changes, no personal settings modifications.

**Limitations:** The optional IQ packing fixture was skipped, CUDA/HIP full builds and real user models were not available or run. End-to-end model readiness and the complete project's 100% milestone remain unconfirmed. Personal models, paths, and scripts are preserved byte-for-byte; ZIP contains no model weights, binaries, or secrets.
