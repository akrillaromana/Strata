# Strata Fork — iteration 060

## Scope

Iteration 060 turns the user's complete `E:\ai\models` inventory into an explicit, read-only personal model catalog and launch set for every model family the current Strata fork really supports. The already-supported external `E:\ai\Strata-data\models\IQ3_S` profile is retained rather than being lost during the schema upgrade. Models still downloading are included by their expected final names and remain fail-closed until the downloads finish.

The 059 defaults remain: PCIe 0.09, MTP/spec-min-p 0.9 and `parallel=2`. Additionally this iteration repairs pip-less Python 3.14 `.venv` environments: every maintained launcher probes the selected Python before RAM staging; the server itself independently invokes the same bootstrap **before importing Jinja2** (also protecting old launchers). The bootstrap uses `python -m ensurepip --upgrade` if pip is absent, then the pinned `requirements.txt` and a second import probe. No model JSON is modified.

## Qwen3.8 Flash-Next profiles

Added/updated profiles and one-line BAT launchers for:

- Alesha Pro abliterated GSQ-RCO IQ3_S;
- SC117 GSQ-RCO abliterated IQ3_S;
- SC117 Swift 1.5 GSQ-RCO abliterated IQ3_S (download in progress);
- UkisAI Swift 1.5 Q4_K_M (download in progress);
- UkisAI Swift 1.5 Q6_K (download in progress; catalog expects all five final shards);
- UkisAI Swift 1.5 GSQ-RCO IQ3_S (download in progress);
- Huihui abliterated UD-Q4_K_XL and Q8_0;
- Unsloth UD-Q4_K_XL, Q6_K and Q8_0.

The configs preserve the established quant-specific launcher contract instead of using one generic argument list: IQ3 shard 2 is `--ple-gguf`; Q4 has the 80-GiB resident budget; Q6/Q8 have 120 GiB and `--ple-require-type Q8_0`; Q6 points to the separate Q6 engine. All qwen4exp variants use shared Flash-Next MTP runtime and `parallel=2`.

## Real Qwen3.6-35B-A3B support

The 059 server already understood the `qwen35moe` family, but the custom native binary did not contain the upstream Qwen3.6 engine. Creating JSON alone would therefore have been false support.

Iteration 060 vendors the required upstream Strata 0.1.45 native source in `vendor/strata-q36-0.1.45/` and provides `BUILD-Q36-ENGINE.ps1/.bat`. It builds an isolated `engine-q36\strata-q36.exe`; the custom qwen4exp/Q6/Q8 engine files are not replaced.

Configured Qwen3.6 profiles:

- UD-Q4_K_XL;
- UD-Q6_K_XL;
- UD-Q6_K;
- UD-Q8_K_XL;
- uncensored HauhauCS Q4_K_P;
- uncensored HauhauCS Q8_K_XL future/download profile.

Qwen3.6 uses `--mtp 2 --batch-mtp` because MTP is embedded in that GGUF family. `--pcie-frac` and `--spec-min-p` are deliberately absent because those qwen4exp controls are not q36 engine options. `parallel=2` still maps to two native batch slots.

The q36 source tree passed a local CMake configure check with CUDA disabled. A real Windows/CUDA `strata-q36.exe` build cannot be performed in the container and must be executed on the user's RTX 3060 via `BUILD-Q36-ENGINE.bat`.

## In-progress and future files

`tools/personal_model_preflight.py`, `tools/personal_models.py`, `LIST-PERSONAL-MODELS.ps1` and `START-PERSONAL-MODEL.ps1` distinguish completed GGUFs from `.part`/`downloading_*` files.

For the requested future uncensored 35B Q8_K_XL profile, an exact filename is not assumed. If the provisional file is absent, exactly one completed `*Q8_K_XL.gguf` may satisfy `model_glob`. The checked-in config remains immutable: the launcher creates a generated runtime JSON with the discovered `--native` path under `logs/personal/runtime-configs/`.

## Deliberately unsupported local inventory

No Strata config is emitted for the local Gemma models, Qwen2.5 Coder models, dense Qwen3.5-9B, or dense Qwen3.8-27B/Swift-27B variants. They are not a current native Strata engine family. The catalog records them under `unsupported_detected` rather than pretending they can run.

## Validation

- combined iteration-060 + 059-defaults + pip-less bootstrap + autotune/calibration/setup + Q6 launch regression suite: **69/69 OK**;
- independent catalog/config/wrapper invariant: **18/18** profiles have exactly one matching BAT launcher (17 from the supplied E:\ai\models inventory plus the existing external RCO profile);
- every qwen4exp profile has `pcie-frac=0.09`, `spec-min-p=0.9`, `parallel=2`;
- every qwen35moe profile has `parallel=2`, embedded MTP drafts=2 and `--batch-mtp`, with no qwen4exp-only PCIe/spec-min-p flags;
- no generated config points to `.part`/`downloading_*` files;
- Python modules compile;
- isolated upstream q36 vendor CMake configure completed successfully with tests/CUDA disabled as a structural check.

See `MODEL_MATRIX.md` for every profile and its launcher.
