# Iteration 024 report — NativeEmbed GPU/host ownership

## Verified defect in 023

`src/core/native_head.cpp::NativeEmbed::load()` assigned fields such as `host_`, `row_`, `bytes_` before all potentially failing pin/map/copy operations. If host pinning succeeded but `cudaHostGetDevicePointer()` failed on CUDA, it returned false without releasing pinned allocation until object destruction, leaving a partially initialized object that could be loaded again. A HIP-only fallback already existed but lacked an exception-safe transaction. This can affect model startup independently of the expert quantization.

## Code changes

- Introduced `include/strata/core/native_embed_allocation.hpp` as a small CUDA-neutral ownership transaction with explicit aliases and independent GPU allocations, fail-safe destructor and `commit`.
- `NativeEmbed::load` creates local stride and size variables; preflights the entire GGUF first, owns allocations in a local transaction, then commits state exactly once after successful copy and alias resolution.
- A failure to pin host memory or map the CUDA/HIP host pointer now attempts GPU VRAM allocation and copy, with correct cleanup in all failure branches.
- `NativeEmbed::load` rejects a second load on an object that is already initialized. `gather_one` and `gather_dev` reject use before successful load.
- CMake registers a CPU-only ownership lifecycle test, and Python source wiring tests ensure the integration is not accidentally omitted.

## What this does not prove

The helper test exercises fake addresses and mock releases, not actual CUDA/HIP device allocation, CUDA kernels or model weights. The translation unit syntax check used fake CUDA declarations only. Complete Unsloth Q6_K / Huihui & Unsloth Q8_0 / IQ3_S and the four MTP sources are not end-to-end verified; Vision and constrained JSON Schema decoding remain open. The user's actual eight GGUF sets and their performance have not been tested.

Original model path inventory and personal launch BAT/PS1/JSON files are unchanged; no runtime binaries or weights were added.
