// Standalone tests of the native expert manifest's arithmetic and multishard path rules.
#include "strata/kernels/cpu/native_layout_safety.hpp"
#include <cstdint>
#include <limits>
#include <iostream>

using namespace strata::kernels::cpu;
int main() {
    int failed = 0;
    auto check = [&](bool ok, const char* msg) {
        if (!ok) { ++failed; std::cerr << "FAIL: " << msg << '\n'; }
    };
    uint64_t next = 0;
    check(native_layout_add(0, 210, 512, next) && next == 107520, "Q6_K blob multiplication");
    check(native_layout_add(4096, 170, 512, next) && next == 91136, "Q8_0 native span");
    check(!native_layout_add(0, 1, 0, next), "zero experts");
    check(!native_layout_add(0, 0, 512, next), "zero blob");
    check(!native_layout_add(UINT64_MAX - 2, 210, 512, next), "overflow product");
    check(!native_layout_add(UINT64_MAX - 10, 1, 32, next), "overflow addition");
    check(native_role_fits(100, 210, 512, 107620), "Q6_K valid file boundary");
    check(!native_role_fits(100, 210, 512, 107619), "Q6_K truncated shard");
    check(!native_role_fits(UINT64_MAX, 210, 512, UINT64_MAX), "overflow shard offset");
    check(native_shard_name_ok(""), "first-shard sentinel");
    check(native_shard_name_ok("Huihui-Q8_0-00004-of-00006.gguf"), "Huihui Q8 multishard");
    check(native_shard_name_ok("Unsloth Q6_K shard.GGUF"), "shard with spaces");
    for (const auto invalid : {"../other.gguf", "..\\other.gguf", "D:other.gguf", "/tmp/other.gguf",
                               "\\\\server.gguf", ".hidden.gguf", "shard.gguf/extra", "shard.txt",
                               "shard.gguf?", "bad\n.gguf"}) {
        check(!native_shard_name_ok(invalid), invalid);
    }
    std::cout << (failed ? "native_layout_safety failed\n" : "native_layout_safety OK\n");
    return failed ? 1 : 0;
}
