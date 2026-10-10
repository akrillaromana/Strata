# Strata Custom — iteration 026

Complete source snapshot based on published 025 (`02ec8ec`). Two CUDA expert SwiGLU Q8_1 quantizers were missing the existing FP16 finite scale/sum and int8 saturation, risking NaNs for large finite activations. Both are aligned with the canonical quantization path; 32-bit product overflows in n_in × ncols now fail before CUDA. See `docs/reports/iteration-026/{REPORT,Q8_NUMERIC_CONTRACT,CHECKS,TASKS}.md`.

Source-only tests: 110 targeted Python, 32 server Python, 8 personal profiles, 55 JS, 8 standalone C++ tests. Unfiltered tools suite timed out in engine-tuning mocks and is not claimed to pass in this iteration. No CUDA toolchain/GPU, user models or E:/R: changes. Source compatibility for all eight personal GGUF models is not end-to-end confirmed.
