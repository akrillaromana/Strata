// Shared CPU/CUDA-source dimension contract for native Q8_1 activation buffers.
// The CUDA quantization entry points index the concatenated activations as int,
// so n_in * ncols must not overflow INT_MAX, even if each component is valid.
#pragma once
#include <limits>

namespace strata::kernels {
constexpr bool native_mmvq_shape_ok(int n_in, int ncols, int block_elems) noexcept {
    return block_elems > 0 && n_in > 0 && (n_in % block_elems) == 0 &&
           ncols >= 1 && ncols <= 8 && n_in <= std::numeric_limits<int>::max() / ncols;
}
} // namespace strata::kernels
