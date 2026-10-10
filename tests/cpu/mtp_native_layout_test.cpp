// Native MTP GGUF-derived runtime: CPU-only parser/geometry checks, no GPU.
#include "strata/core/mtp_native_layout.hpp"
#include <cassert>
#include <cstdint>
#include <sstream>
#include <string>
using strata::core::MtpNativeLayout;
using strata::core::mtp_native_layout;
static bool accept(const std::string& manifest, uint64_t bytes, uint64_t n = 2, uint64_t h = 64, uint64_t ff = 32) {
    std::istringstream in(manifest); MtpNativeLayout l; std::string err;
    return mtp_native_layout(in, bytes, n, h, ff, l, err);
}
int main() {
    // 2x(2*32*64*2 + 64*32*2) = 24576 bytes BF16/BF16.
    assert(accept("mtp_native_experts_v1 bf16 bf16 2 64 32\n", 24576));
    // 2x(2*32*64/32*34 + 64*32/32*34) = 13056 Q8_0/Q8_0.
    assert(accept("mtp_native_experts_v1 q8_0 q8_0 2 64 32\n", 13056));
    assert(accept("mtp_native_experts_v1 q8_0 bf16 2 64 32\n", 2 * (4352 + 4096)));
    assert(!accept("mtp_native_experts_v2 q8_0 q8_0 2 64 32\n", 13056));
    assert(!accept("mtp_native_experts_v1 q2_0 bf16 2 64 32\n", 13056));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 2 64 32\n", 13055));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 3 64 32\n", 13056));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 2 65 32\n", 13056));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 2 64 31\n", 13056));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 -1 64 32\n", 13056));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 2 64 32 extra\n", 13056));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 2 64 32\nadditional\n", 13056));
    assert(!accept("mtp_native_experts_v1 q8_0 q8_0 2 64 32\n", 13056, 512));
    return 0;
}
