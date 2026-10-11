# Iteration 027 — make MTP failure handling safe for Q8_0/BF16 speculative runtime

**Base:** complete iteration 026 ZIP; owner's successfully published fork HEAD `d65d1a7`.

## Defects fixed

1. **Process-wide KV state leak on MTP load failure:** `src/core/mtp.cpp` temporarily changes `qsa_set_kv_hybrid()` / `qsa_set_kv_int8()` to initialize the draft layer. Its early returns from `cudaMalloc()` or `qsa_state_init()` bypassed both restore calls. Added a non-copyable `MtpScopedKvMode` RAII guard with the original restore order (int8, then hybrid); all returns and exception unwinding restore the main model's KV mode. The temporary KV switch stays scoped only around allocation/initialization, as before.
2. **Leaked pinned host allocation on mapped-pointer failure:** `mapped()` allocated with `cudaHostAlloc()` and returned false directly if `cudaHostGetDevicePointer()` failed. New `mtp_mapped_allocation()` publishes host/device pointers only after success, zeroes the host buffer on success, and frees the temporary allocation on partial/alias failure. Existing MTP host mapping call sites use it transparently.
3. **Dangling state arena pointer on KV fallback:** a failed streamed-KV initialization freed `state_arena_` and attempted a resident fallback. If that allocation failed, the drafter destructor could later double-free the stale pointer. Set it to `nullptr` immediately after free.
4. **Repeat load leaks VRAM:** calling `MtpDrafter::load` on an already or partially loaded instance overwrote persistent handles. It now fails closed and requires a fresh instance. Failure to query the selected CUDA device is also handled explicitly.
5. **Native BF16/Q8_0 CUDA launch dimensions:** `mtp_native_experts` previously allowed `hits` not divisible by `k`, leading to incorrect per-token indexing, and could overflow 32-bit `hits * ff + 255` or `2 * ff`. `mtp_native_launch_shape()` checks top-k grouping, types, geometry and integer bounds before dispatch.

## Verification performed

- 101 focused Python cases across MTP, Q6_K/Q8_0, model catalog and loading policies (includes 7 new source integration checks).
- 32 server Python tests; 8 personal profile tests; 55 JavaScript tests.
- 10 independent C++ tests compiled with `g++ -std=c++17 -O2 -Wall -Wextra -Werror` and executed, including the new `mtp_load_safety_test` with fault injection and compile-time shape assertions.
- `python -m compileall -q tools serve setup.py`.
- Separate Git synthetic baseline 026 stage allowlist and `git -c core.whitespace=cr-at-eol diff --cached --check` (details in CHECKS.txt).

## Deliberate limitations

No full CUDA/HIP build or real MTP/BF16/Q8_0 GGUF inference was performed. Unit tests do not establish GPU correctness. Native Q6_K is still an opt-in CUDA build flag. Full original Q8_0 n-gram and GSQ-RCO IQ3_S model compatibility, actual MTP/shared topologies, mmproj/vision, true token-constrained JSON Schema decoding and donor 0.1.41 features remain open. Do not label the entire fork 100% complete.

The project-specific `qsa_state_init()` owns additional pinned staging/KV storage during session lifetime; its broader lifecycle/cleanup is a separate audit item and is **not** claimed resolved here.
