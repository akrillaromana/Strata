# Strata Fork — iteration 059

## Scope

Iteration 059 is built on the full iteration 058 codebase and applies the user's new runtime defaults plus a Windows launcher repair found from a real Q4_K_XL startup trace.

## Product defaults

- `--pcie-frac`: **0.09** everywhere by default.
- `--spec-min-p` / MTP threshold: **0.9** everywhere by default.
- real engine parallelism: **enabled by default with `parallel: 2`**, which the server maps to `--batch 2`.
- explicit user/runtime/autotune values continue to override defaults.
- `parallel: 1` / setup `--parallel 1` explicitly disables batching.
- MTP `1.0` remains in the tuning grid.

All 25 active MTP JSON profiles/examples in the root, PERSONAL_START, q4-local-profiles and native-high-quant locations were checked for the exact `0.09 / 0.9 / parallel=2` contract.

## Windows startup repair

A real launch reached `serve/frontend.py` and failed with `ModuleNotFoundError: No module named 'jinja2'`. `requirements.txt` already pins Jinja2, but an older `.venv` can survive a code update without receiving the new dependency.

`STRATA-MODEL-LAUNCH-COMMON.ps1` now provides `Ensure-StrataServerPythonDependencies`:

1. before heavy RAM/model staging it probes imports required by the server (`jinja2`, `regex`, `yaml`, `requests`, `PIL`, `psutil`, `jsonschema`, `referencing`);
2. if the probe fails, it verifies/repairs pip, installs the pinned project `requirements.txt` into the selected Python environment, and re-runs the import probe;
3. only after a successful probe does model/RAM preparation continue.

The check is wired into Q4, Huihui, Q6, Q8 and IQ3 launchers and their mirrored launcher copies. The process guard also recognizes the separate Q6 `engine-q6\\strata.exe`.

PowerShell's refusal to execute a file from the current directory by bare name is not a BAT defect: `START-Q4-K-XL.bat` must be invoked as `.\\START-Q4-K-XL.bat` unless the project directory is explicitly placed on PATH. The actual project failure after the BAT started (missing Jinja2) is repaired here.

## Engine/setup/calibration

- main and SYCL direct `pcie_frac` fallback changed from 0.26 to 0.09;
- setup-generated engine args changed to `0.09 / 0.9`;
- setup now emits `parallel: 2` when the user did not explicitly set `--parallel`;
- calibration reset/default changed to `0.09 / 0.9`;
- existing explicit calibration/autotune continues to win;
- PCIe parity diagnostics now include 0.09 while retaining older comparison points.

## Validation

- `tools.test_iteration059_defaults`: **4/4 OK**.
- targeted defaults/profile/Q6/calibration/autotune/setup-update tests: related assertions pass after updating the expected product default.
- setup golden baseline regenerated; baseline/`--yes`/refusal tests pass. Two pre-existing `test_enter_for_every_question` cases still intentionally stop UD-Q4_K_XL on 32 GiB and 47 GiB RAM because the setup requirement remains >=48 GiB; these are unrelated to iteration 059.
- `serve.test_parallel.ParallelArgs` passed; multiple concurrent/recovery service cases passed before the long aggregate test exceeded the container time budget, with no assertion failure before timeout.
- Python compilation checks passed for modified Python modules.

## Preserved iteration 058 behavior

Selective upstream Strata 0.1.45 API/reasoning/tool-call/request hardening, image/vision helpers, sm_86 wide dequant, immutable model JSON, live TUNE/TUNED and custom Q6/Q8/runtime paths remain intact.

## Git publication delta

Last confirmed published base: `0c1a09f` (iteration 057). The 057→059 manifest contains **121 paths: 58 new + 63 modified, 0 deletions**. This deliberately includes the unconfirmed iteration 058 backport plus iteration 059 so nothing is skipped if 058 was not pushed separately.
