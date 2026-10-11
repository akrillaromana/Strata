# Owner's model support: current code evidence vs validated runtime

None of these model variants has been executed end-to-end in iteration 027. Header preflight, source-level checks and synthetic CUDA-contract tests are NOT real inference results.

| Model | Model shards | Current model-specific block |
|---|---:|---|
| Unsloth UD-Q4_K_XL | 4 | Existing profile/kernel path; no owner-model E2E test in this iteration |
| Huihui UD-Q4_K_XL | 4 | Existing profile/kernel path; no owner-model E2E test in this iteration |
| Unsloth Q6_K | 5 | Q6 expert kernel requires opt-in compilation; complete numeric prefill/expert parity still open |
| Unsloth Q8_0 | 6 | Original own Q8_0 PLE/n-gram preflight exists; full native/compute path not verified |
| Huihui Q8_0 | 6 | Same plus abliterated GGUF metadata/tensor differences must be verified |
| alesha-pro GSQ-RCO IQ3_S | 2 | Exact customized topology/quantization not verified |
| SC117 GSQ-RCO IQ3_S | 2 | Exact customized topology/quantization not verified |
| Additional personal RCO IQ3_S under E:\\ai\\Strata-data\\models\\IQ3_S | 2 | Exact customized topology/quantization not verified |

Additional Unsloth MTP GGUF candidates (primary BF16/Q8_0 and separate shared BF16/Q8_0) are not full MTP runtime directories. Iteration 027 improves the compiled-source native drafter failure handling; it does not validate their unprovided exact tensor content. mmproj/vision is likewise still incomplete.
