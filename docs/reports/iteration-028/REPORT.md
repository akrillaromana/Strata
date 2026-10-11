# Iteration 028 — full source report

**Parent:** full 027 archive, owner's published GitHub commit `d5304f3` (`strata-v0.1.39-custom`).

**Two defects fixed:**

1. `q8_ple_preflight.locate()` previously checked the original Q8_0 PLE tensor only, so an unrelated invalid tensor in the same shard or a broken model split could pass its headline "Q8_0 confirmed" result. It now runs the existing shared full-shard audit before success; error reporting continues to distinguish a missing/wrong Q8 table from corrupt neighboring tensors.
2. CUDA and experimental SYCL `native_ple_postops_batch` used unchecked `unsigned(T)*4` and unchecked block calculations, accepted aliased scratch/input/weight pointers, and launched GPU work before ensuring valid buffer geometry. Both backends now call the same standalone C++ guard. The C++ review caught and fixed an initially overstrict alignment assumption for FP16 conv weights.

**Regression evidence:** See `CHECKS.txt`. Full tools discovery: 543 tests, 0 FAIL, 0 ERROR, 2 SKIP; 43 serve Python; 10 personal models; 55 JS; 7 standalone C++; compileall. Changes to CUDA/SYCL source were checked syntactically/structurally but no GPU backend build occurred.

**Scope:** source tree only, personal model JSON and all BAT/PS1/JSON profiles unchanged. Do not advertise complete CUDA Q6_K/Q8_0, Huihui, RCO IQ3_S, MTP or Vision support. The end-to-end compatibility matrix remains unverified. Continued work is listed in `TASKS.md`.
