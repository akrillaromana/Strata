# Iteration 024 — safe native embedding allocations

Full custom 0.1.39 source tree through iteration 024. Starting base: published iteration 023 (`645b2be`).

`NativeEmbed::load()` now stages pinned-host and VRAM allocations transactionally and only publishes the pointers, type and dimensions on success. A mapped-host alias failure falls back to VRAM for CUDA and HIP alike, whereas previously CUDA returned an error with a retained pinned buffer. Failed copies or device allocation release every temporary allocation. Second loads and gathers before successful loads are rejected. No weights or local installation have been modified.

A new header-only ownership contract allows CPU-only lifetime tests without CUDA. The C++ host translation unit was syntax-checked with local CUDA declarations; **this is NOT a CUDA/engine build or a real-model execution**.

Real model compatibility remains unverified for all eight personal variants, including Unsloth Q6_K and Huihui Q8_0. See `docs/reports/iteration-024/READINESS_MATRIX.md`.
