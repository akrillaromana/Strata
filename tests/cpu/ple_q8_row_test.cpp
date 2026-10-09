// Native Q8_0 PLE regression: the 160-value row must retain five complete GGUF Q8_0 blocks.
// CPU only; this also catches accidental reductions of PLE_ROW_BYTES_MAX to the FP8 width.
#include "strata/kernels/ngram.hpp"
#include "strata/artifact/dequant.hpp"
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

int main() {
    using namespace strata::kernels;
    static_assert(PLE_HEAD_DIM == 160);
    static_assert(PLE_ROW_BYTES_Q8_0 == 170);
    static_assert(PLE_ROW_BYTES_MAX >= PLE_ROW_BYTES_Q8_0);
    std::array<uint8_t, PLE_ROW_BYTES_Q8_0> row{};
    std::array<float, PLE_HEAD_DIM> decoded{};
    // IEEE-754 binary16 1.0 = 0x3c00; 0.5 = 0x3800; 2.0 = 0x4000.
    constexpr uint16_t scales[5] = {0x3c00, 0x3800, 0x4000, 0x3c00, 0x3800};
    const float expected_scales[5] = {1.0f, 0.5f, 2.0f, 1.0f, 0.5f};
    for (size_t b = 0; b < 5; ++b) {
        auto* blk = row.data() + b * 34;
        blk[0] = (uint8_t) (scales[b] & 255u);
        blk[1] = (uint8_t) (scales[b] >> 8);
        for (int j = 0; j < 32; ++j) blk[j + 2] = (uint8_t) (int8_t) (j - 16);
        strata::dequantize_q8_0(blk, decoded.data() + b * 32);
    }
    for (size_t b = 0; b < 5; ++b) {
        for (int j = 0; j < 32; ++j) {
            if (decoded[b * 32 + (size_t) j] != expected_scales[b] * (j - 16)) {
                std::fprintf(stderr, "Q8_0 PLE row mismatch: block=%zu element=%d\n", b, j);
                return 1;
            }
        }
    }
    std::puts("native Q8_0 PLE 170-byte row: OK");
    return 0;
}
