# Iteration 059 tasks

- [x] Set global PCIe default to 0.09.
- [x] Keep global MTP/spec-min-p default at 0.9.
- [x] Enable real two-slot engine parallelism by default (`parallel=2` / `--batch 2`).
- [x] Apply defaults to all active JSON profiles/examples and embedded launcher/setup/engine fallbacks.
- [x] Preserve explicit user/autotune overrides and immutable model JSON behavior.
- [x] Repair stale Windows `.venv` automatically before heavy model/RAM staging.
- [x] Cover Q4/Huihui/Q6/Q8/IQ3 launcher families.
- [x] Include separate Q6 engine in running-process guard.
- [x] Update tests/golden data for the new product defaults.
- [x] Validate parallel server path and product invariants.
- [x] Build full archive and Git publication manifests from last confirmed published iteration 057.

Future/optional: deep native upstream `--batch-mtp` C++ transplant remains separate from ordinary `--batch 2` parallelism and is not required for the current two-request test.
