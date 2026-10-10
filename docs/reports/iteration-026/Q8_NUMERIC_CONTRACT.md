# Q8_1 SwiGLU quantization contract

The Q8_1 block contains 32 signed int8 codes, a half-precision scale, and a half-precision sum of **unquantized** activations. The finite-input behavior after 026 is:

- `amax = max(abs(x[i]))`; `sum` is the warp butterfly sum of original `x[i]`.
- `d = clamp_signed(amax/127, 65504)` in floating point before half storage.
- `q[i] = saturate(roundf(x[i]/d), -127,127)`, with zero codes for zero-maximum blocks.
- Half-precision `d` and `sum` store `clamp_signed(value, 65504)`; the helper intentionally does not hide NaN inputs.
- The grouped fused MoE path calls the existing shared `q8_1_store`, avoiding duplicate rounding logic.

Examples for finite source activations (CPU synthetic reference):

| 32-value block | Legacy fused result | Fixed fused result |
|---|---|---|
| zeros | d=0, sum=0 | unchanged |
| values within typical activation range | finite d and sum | same rule |
| 32 × 3000 | half sum=+inf | half sum=65504 |
| 32 × -3000 | half sum=-inf | half sum=-65504 |
| one -20,000,000 and 31 × 0.5 | d overflows half, sum overflows half | finite d, finite sum, int8 in [-127,127] |

This correction prevents infinity being introduced by *these* quantizers from otherwise finite input. It does not certify arbitrary downstream tensor finiteness, model quality or CUDA runtime behavior.
