# Model test-readiness — source audit, iteration 024

**Status of full functional validation: NOT READY TO CLAIM ALL EIGHT WORK.**

| Personal model id | Variant | Code/source status | Prerequisite before end-to-end claim |
|---|---|---|---|
| `unsloth_q4` | Unsloth UD-Q4_K_XL, 4 shards | Existing known personal launch path | Build/runtime smoke and numerical token checks not conducted on this fork |
| `huihui_q4` | Huihui UD-Q4_K_XL, 4 shards | Existing profile | Model-specific GGUF architecture/experts, outputs not verified |
| `unsloth_q6` | Unsloth Q6_K, 5 shards | Q6_K kernels require opt-in `STRATA_Q6K_EXPERTS` + `STRATA_MMQ_KQUANTS`, off by default | Native gate/up/down, MMQ/prefill and real weights unverified |
| `unsloth_q8` | Unsloth Q8_0, 6 shards | Q8_0 code paths and strict native original-shard PLE guards | Q8_0 PLE/original n-gram and complete generation unverified |
| `huihui_q8` | Huihui Q8_0, 6 shards | Same native Q8 path, model-specific PLE policy | Huihui GGUF expert/PLE semantics and complete generation unverified |
| `alesha_rco_iq3s` | GSQ-RCO IQ3_S, 2 shards | IQ3_S kernel routes exist | This exact RCO architecture, quantized weights and outputs unverified |
| `sc117_rco_iq3s` | GSQ-RCO abliterated IQ3_S, 2 shards | IQ3_S kernel routes exist | This exact RCO architecture, quantized weights and outputs unverified |
| `personal_rco_iq3s` | separate RCO IQ3_S, 2 shards on `E:\ai\Strata-data\models\IQ3_S` | Preserve separate existing personal path | This exact model path, output and generated pack unverified |

Additional files are not standalone model-ready paths: original MTP BF16, MTP Q8_0, shared BF16 and shared Q8_0 GGUF still require source-topology checks and runtime preparation; `mmproj` files require complete vision encoder integration. This iteration does **not** instruct the owner to build or launch any models. No inference about runtime success follows merely from static source code and GGUF header checks.

A useful *future* acceptance gate for a model needs a successful full compile, verified exact GGUF files, correct pack/MTP/PLE provenance, numerical parity checks on the generated model, generation smoke tests, stability/quality checks and then optional vision support. Those tests are not included in the source-code completeness percentage.
