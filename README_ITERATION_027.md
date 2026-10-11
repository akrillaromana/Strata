# Strata Custom — iteration 027

Full source iteration from the owner's confirmed GitHub 026 commit `d65d1a7`.

MTP BF16/Q8_0 reliability fixes: the drafter restores process-wide QSA KV format flags on *every* allocation/init failure, releases pinned host allocations if CUDA fails to map them, does not leave a dangling arena pointer after the streamed-KV fallback, and rejects loading the same (even partially initialized) MTP object twice. Native MTP CUDA shape checks now reject incompatible `hits/top-k` and 32-bit overflow before launch.

Checks include 10 standalone CPU-only C++ test programs built with `-Werror`, 101 relevant Python cases, 32 server Python cases, 8 personal profile cases, 55 JavaScript cases, and source wiring checks. No full CUDA compilation, actual GGUF file, GPU-parity or Windows executable was run. All 8 model variants and E:/R: profiles remain untouched. Source-only correctness is **not** proven end-to-end support for all personal models.

See `docs/reports/iteration-027/` and `CONTINUE_PROMPT.md`.
