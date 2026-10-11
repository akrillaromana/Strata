#pragma once

#include <cstdint>
#include <limits>

namespace strata::kernels {

// CUDA launches use 32-bit products for 2*ff and (hits*ff+255).
// Reject malformed shapes before kernel dispatch rather than overflowing an
// integer or indexing an input token beyond hits/k rows.
constexpr bool mtp_native_launch_shape(int hits, int k, int experts, int hidden, int ff,
                                        int gate_kind, int down_kind) noexcept {
    return hits >= 1 && hits <= 128 && k >= 1 && k <= hits && hits % k == 0 &&
           experts >= 1 && hidden >= 32 && ff >= 32 && hidden % 32 == 0 && ff % 32 == 0 &&
           (gate_kind == 8 || gate_kind == 30) && (down_kind == 8 || down_kind == 30) &&
           ff <= (std::numeric_limits<int>::max() - 255) / hits &&
           ff <= std::numeric_limits<int>::max() / 2;
}

} // namespace strata::kernels
