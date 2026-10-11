# Iteration 029 — grouped expert / IQ3_S-Q6_K-Q8_0 runtime safety

**Parent:** complete Strata iteration 028 archive, published GitHub SHA `3c7659f` on branch `strata-v0.1.39-custom` (confirmed by owner-supplied Git push log). No upstream branch or CUDA runtime replacement.

## Fixed production-source errors

1. **Unvalidated native IQ MMVQ kernel arguments.** `src/kernels/cuda/iq_kernels.cu::iq_mmvq` previously computed a row byte stride and launched kernels without checking a whole quantization block in each row, `n_out`, column range, output indexing (`n_out*ncols`), or integer overflow in the launch-grid expression `n_out+3`. Malformed dimensions could reach the GPU. The shared `iq_mmvq_shape_ok` guard now rejects these inputs before computing the row stride or launching. This matters to the GSQ-RCO IQ3_S routed-expert path and opt-in Q6_K; the normal native Q8_0 caller already had partial shape checks.
2. **A dropped model/unsupported format could terminate the engine.** `iq_mmvq` previously used `std::exit(1)` in its unsupported type branch. The entry now raises `std::invalid_argument` instead so caller-level error handling may report it without unconditionally terminating the process. This change is specific to the MMVQ entry; other historical `std::exit()` sites still need a separate audit.
3. **Potential signed arithmetic UB in expert availability checks.** `native_expert_supported` evaluated `(n_ff*n_embd) % 256` with signed 64-bit arithmetic, although `n_embd % 256 == 0` alone suffices. That redundant multiplication could overflow for corrupted GGUF metadata. Replaced with bounded dimension and divisibility checks.
4. **Unchecked grouped expert GPU allocation sizes.** `native_expert_layout` formerly multiplied untrusted dimensions for `up_off`, `down_off`, `bytes`, and `native_expert_scratch_bytes` computed multiple products, additions and 256-byte alignments without checked arithmetic. The new CPU-testable `iq_expert_offsets`, `iq_expert_scratch_bytes_checked`, `iq_safe_add/mul/align_256` perform all arithmetic safely and reject invalid geometry *before* unsigned byte-count conversion.
5. **Unsafe Q8_1 activation quantization dimensions.** `quantize_q8_1_rows` did signed `n_rows*n_cols` before validation, accepted row widths not divisible by 32, and could overflow GPU grid calculations. A checked row/column contract now runs before multiplication, preserving `n_rows=0` no-op and CUDA's supported default-stream behavior.

## Model relevance / boundaries

- **RCO IQ3_S (three distinct variants):** grouped IQ kernels now reject malformed dimensions without corrupting allocations; this does NOT validate the three original GGUF tensor layouts.
- **Unsloth Q6_K (five shards):** grouped Q6_K expert sizes and quantizer input geometry are checked in the opt-in code path; the CUDA build switches `STRATA_Q6K_EXPERTS` and `STRATA_MMQ_KQUANTS` remain opt-in. This does NOT finish or verify full Q6_K model inference.
- **Unsloth/Huihui Q8_0 (six shards each):** input quantization and grouped allocation geometry is hardened; their native original n-gram/PLE numerical runtime remains unverified.
- **BF16/Q8_0 MTP shared sources:** unchanged; actual GGUF topology and GPU parity unverified.

**Source-only test evidence:** `CHECKS.txt`. Full tools suite: 553 tests, 0 failures/errors, 2 skips; Python server + profile 53, JavaScript 55, ten CPU-only standalone C++ with `-Wall -Wextra -Werror`, Python compileall. CUDA/HIP was NOT compiled or executed and no real model weights were read. User profiles and all other archive contents are preserved byte for byte.
