# Iteration 060 — local model matrix

The inventory is intentionally limited to model architectures that this fork can actually execute:

- `qwen4exp` — Qwen3.8 Flash-Next and compatible fine-tunes;
- `qwen35moe` — Qwen3.6-35B-A3B through the isolated upstream-0.1.45 `strata-q36` sidecar.

`parallel=2` is the product default for every profile. Qwen3.8 profiles use `pcie-frac=0.09`, `spec-min-p=0.9`, `spec=4`, context 262144 and INT8 KV. Qwen3.6 uses its own embedded MTP (`--mtp 2 --batch-mtp`); Qwen3.8 `pcie/spec-min-p` flags do not apply to that engine family.

## Configured profiles

There are 18 catalogued launch profiles: 17 derived from the supplied `E:\ai\models` listing plus the pre-existing `E:\ai\Strata-data\models\IQ3_S` profile retained for backward compatibility. Existing canonical IDs are preserved; newer hyphenated names are aliases where applicable.

| State from supplied inventory | ID | Architecture | Quant | Launcher |
|---|---|---|---|---|
| READY | `alesha_rco_iq3s` (`alesha-rco-iq3s`) | qwen4exp | IQ3_S | `START-MODEL-ALESHA-RCO-IQ3S.bat` |
| READY | `sc117_rco_iq3s` (`sc117-rco-abliterated-iq3s`) | qwen4exp | IQ3_S | `START-MODEL-SC117-RCO-ABLITERATED-IQ3S.bat` |
| EXISTING | `personal_rco_iq3s` | qwen4exp | IQ3_S | `START-MODEL-PERSONAL-RCO-IQ3S.bat` |
| PENDING | `sc117-swift-rco-abliterated-iq3s` | qwen4exp | IQ3_S | `START-MODEL-SC117-SWIFT-RCO-ABLITERATED-IQ3S.bat` |
| PENDING | `ukisai-swift-q4-k-m` | qwen4exp | Q4_K_M | `START-MODEL-UKISAI-SWIFT-Q4-K-M.bat` |
| PENDING | `ukisai-swift-q6-k` | qwen4exp | Q6_K | `START-MODEL-UKISAI-SWIFT-Q6-K.bat` |
| PENDING | `ukisai-swift-rco-iq3s` | qwen4exp | IQ3_S | `START-MODEL-UKISAI-SWIFT-RCO-IQ3S.bat` |
| READY | `huihui_q4` (`huihui-q4-k-xl`) | qwen4exp | UD-Q4_K_XL | `START-MODEL-HUIHUI-Q4-K-XL.bat` |
| READY | `huihui_q8` (`huihui-q8-0`) | qwen4exp | Q8_0 | `START-MODEL-HUIHUI-Q8-0.bat` |
| READY | `unsloth_q4` (`unsloth-q4-k-xl`) | qwen4exp | UD-Q4_K_XL | `START-MODEL-UNSLOTH-Q4-K-XL.bat` |
| READY | `unsloth_q6` (`unsloth-q6-k`) | qwen4exp | Q6_K | `START-MODEL-UNSLOTH-Q6-K.bat` |
| READY | `unsloth_q8` (`unsloth-q8-0`) | qwen4exp | Q8_0 | `START-MODEL-UNSLOTH-Q8-0.bat` |
| READY | `q36-ud-q4-k-xl` | qwen35moe | UD-Q4_K_XL | `START-MODEL-Q36-UD-Q4-K-XL.bat` |
| READY | `q36-ud-q6-k-xl` | qwen35moe | UD-Q6_K_XL | `START-MODEL-Q36-UD-Q6-K-XL.bat` |
| READY | `q36-ud-q6-k` | qwen35moe | UD-Q6_K | `START-MODEL-Q36-UD-Q6-K.bat` |
| READY | `q36-ud-q8-k-xl` | qwen35moe | UD-Q8_K_XL | `START-MODEL-Q36-UD-Q8-K-XL.bat` |
| READY | `q36-uncensored-q4-k-p` | qwen35moe | Q4_K_P | `START-MODEL-Q36-UNCENSORED-Q4-K-P.bat` |
| PENDING/future | `q36-uncensored-q8-k-xl` | qwen35moe | Q8_K_XL | `START-MODEL-Q36-UNCENSORED-Q8-K-XL.bat` |

For the future uncensored Q8_K_XL publisher filename the catalog also carries `model_glob=*Q8_K_XL.gguf`. The launcher only accepts exactly one completed matching `.gguf`; `.part` and `downloading_*` files are never selected. If the real final filename differs from the provisional catalog filename, a generated JSON is written only under `logs/personal/runtime-configs/`; the checked-in config is not changed.

## Quant-specific parity with existing launchers

- IQ3_S keeps the established two-file contract: shard 1 is `--native`, shard 2 is `--ple-gguf`.
- Q4-family profiles use resident budget 80 GiB plus `adapt-every=0`, `adapt-swaps=0`, `prompt-cache=0`.
- Q6_K uses the separate `engine-q6\\strata.exe`, resident budget 120 GiB and `--ple-require-type Q8_0`.
- Q8_0 uses resident budget 120 GiB and `--ple-require-type Q8_0`.
- Flash-Next Swift/RCO fine-tunes use the common prepared Flash-Next MTP runtime `E:\\ai\\Strata-data\\mtp\\rt` rather than inventing a model-specific MTP runtime.

## Downloading models

Profiles exist before downloads finish. `START-PERSONAL-MODEL.ps1` checks all final GGUF names before pack/tokenizer preparation. While only `.part`/`downloading_*` files exist it exits with a list of missing final files and current partial files. When the final files appear, the same launcher/config becomes usable without editing it.

## Detected models intentionally not configured

The supplied inventory also contains Gemma variants, Qwen2.5 Coder, dense Qwen3.5-9B and dense Qwen3.8-27B/Swift-27B variants. These are not `qwen4exp` or `qwen35moe`; the current Strata engine has no native runtime family for them. They remain in `data/personal_models.json -> unsupported_detected` with the reason instead of receiving misleading launch configs.
