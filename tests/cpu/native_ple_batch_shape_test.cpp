#include "strata/kernels/native_ple_batch_shape.hpp"
#include <cassert>
#include <climits>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

using namespace strata::kernels;

template <typename Error, typename F>
bool rejects(F fn) {
    try { fn(); } catch (const Error&) { return true; }
    return false;
}

int main() {
    assert(rejects<std::invalid_argument>([]{ (void)native_ple_batch_shape(0); }));
    assert(rejects<std::invalid_argument>([]{ (void)native_ple_batch_shape(-1); }));
    const auto a = native_ple_batch_shape(1);
    assert(a.rows == 4 && a.blocks == 40);
    assert(a.key_bytes == 40960 && a.value_bytes == 10240 && a.gate_bytes == 16);
    const auto b = native_ple_batch_shape(16);
    assert(b.rows == 64 && b.blocks == 640 && b.key_bytes == 16 * 40960);
    assert(native_ple_batch_shape(100000).rows == 400000);
    assert(rejects<std::length_error>([]{ (void)native_ple_batch_shape(INT_MAX); }));

    alignas(16) float storage[64] = {};
    const NativePleBatchSpan valid[] = {{storage, 32}, {storage + 8, 48}, {storage + 20, 16}};
    native_ple_batch_nonoverlap(valid, 3);
    const NativePleBatchSpan touching[] = {{storage, 32}, {storage + 8, 16}};
    native_ple_batch_nonoverlap(touching, 2);
    const NativePleBatchSpan overlap[] = {{storage, 36}, {storage + 8, 16}};
    assert(rejects<std::invalid_argument>([&]{ native_ple_batch_nonoverlap(overlap, 2); }));
    const NativePleBatchSpan null_span[] = {{nullptr, 8}};
    assert(rejects<std::invalid_argument>([&]{ native_ple_batch_nonoverlap(null_span, 1); }));
    const NativePleBatchSpan unaligned[] = {{reinterpret_cast<void*>(reinterpret_cast<std::uintptr_t>(storage) + 2), 8}};
    assert(rejects<std::invalid_argument>([&]{ native_ple_batch_nonoverlap(unaligned, 1); }));
    const NativePleBatchSpan half_aligned[] = {
        {reinterpret_cast<void*>(reinterpret_cast<std::uintptr_t>(storage) + 2), 8, alignof(std::uint16_t)}
    };
    native_ple_batch_nonoverlap(half_aligned, 1);
    const NativePleBatchSpan invalid_alignment[] = {{storage, 8, 3}};
    assert(rejects<std::invalid_argument>([&]{ native_ple_batch_nonoverlap(invalid_alignment, 1); }));
    const NativePleBatchSpan overflow[] = {{reinterpret_cast<void*>(std::uintptr_t(-4) & ~std::uintptr_t(3)), 16}};
    assert(rejects<std::invalid_argument>([&]{ native_ple_batch_nonoverlap(overflow, 1); }));
    return 0;
}
