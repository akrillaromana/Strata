# 029 shared IQ grouped / batch compute contract

`include/strata/kernels/iq_launch_safety.hpp` is CUDA-free and is included in `src/kernels/cuda/iq_kernels.cu`.

- MMVQ: `n_in` > 0, `n_out` > 0, 1 <= `ncols` <= 8, `n_in` divisible by actual weight block width (`Q8_0=32`, `Q2_0=64`, `Q6_K/IQ3_S=256`); `n_in*ncols` and `n_out*ncols` must fit signed 32-bit indexing, as must `n_out+3` for the 4-row grid.
- Quantizer: `n_rows >= 0`, `n_cols > 0` divisible by 32, `n_rows*n_cols` fits signed 32-bit work indexing; zero-row calls remain a no-op. Device pointers are required for nonzero rows; null CUDA default stream remains accepted.
- Grouped expert geometry: `n_embd/n_ff` within 32-bit kernel dimensions, nonzero row bytes; compute `n_ff*gate_row`, `2*up_off`, `n_embd*down_row` and sum with overflow detection.
- Grouped scratch: valid positive `cap` and `n_ff` multiple of 32; reserve three separately rounded FP32 gate/up/swiglu chunks and one Q8_1 activation chunk, with each multiplication, 256-byte round-up and addition checked.
- Counterexample rejected: malformed `n_out = INT_MAX` overflows original grid expression `(n_out+3)/4`; malformed `n_in=128` Q6_K truncates per-row blocks; malformed `n_rows=INT64_MAX` overflows signed product before quantization.
- Golden synthetic geometry: Q6_K gate/up `[640,2560]`, 2100 B/row and Q8_0 down `[2560,640]`, 680 B/row => `4,428,800`-byte expert; IQ3_S gate/up 1100 B/row and Q2_0 down 180 B/row => `1,868,800` bytes. Scratch `80 x 640` => `672,000` bytes.

These are source-level allocation contracts and cannot replace numerical GPU parity, real shard inspection or an authorized full CUDA build.
