#include "strata/kernels/iq_launch_safety.hpp"
#include <cassert>
#include <climits>
#include <cstdint>
#include <limits>
#include <stdexcept>
using namespace strata::kernels;

template<class E, class Fn> bool fails(Fn f) {
    try { f(); } catch (const E&) { return true; }
    return false;
}
int main() {
    // The native Q6_K, Q8_0 and GSQ-RCO IQ3_S batch contracts.
    assert(iq_mmvq_shape_ok(2560, 512, 8, 256)); // Q6_K or IQ3_S
    assert(iq_mmvq_shape_ok(2560, 512, 8, 32));  // Q8_0
    assert(iq_mmvq_shape_ok(640, 2560, 1, 32));
    assert(!iq_mmvq_shape_ok(128, 512, 1, 256));
    assert(!iq_mmvq_shape_ok(2560, 0, 1, 256));
    assert(!iq_mmvq_shape_ok(2560, 512, 9, 256));
    assert(!iq_mmvq_shape_ok(2560, INT_MAX, 1, 256)); // grid (n_out+3) overflow
    assert(!iq_mmvq_shape_ok(2560, INT_MAX / 2 + 1, 2, 256));
    assert(!iq_mmvq_shape_ok(INT_MAX - 127, 512, 2, 256));
    assert(!iq_mmvq_shape_ok(2560, 512, -1, 256));
    assert(!iq_mmvq_shape_ok(2560, 512, 1, 0));

    assert(iq_quantize_rows_shape_ok(8, 2560));
    assert(iq_quantize_rows_shape_ok(0, 2560));
    assert(!iq_quantize_rows_shape_ok(-1, 2560));
    assert(!iq_quantize_rows_shape_ok(8, 2559));
    assert(!iq_quantize_rows_shape_ok(INT64_MAX, INT64_MAX));
    assert(!iq_quantize_rows_shape_ok(INT_MAX, 2560));

    const auto q6 = iq_expert_offsets(2100, 680, 2560, 640);
    assert(q6.up == 1344000 && q6.down == 2688000 && q6.total == 4428800);
    const auto iq3 = iq_expert_offsets(1100, 180, 2560, 640);
    assert(iq3.up == 704000 && iq3.down == 1408000 && iq3.total == 1868800);
    assert(fails<std::invalid_argument>([]{ (void)iq_expert_offsets(0, 680, 2560, 640); }));
    assert(fails<std::invalid_argument>([]{ (void)iq_expert_offsets(100, 100, -1, 640); }));
    assert(fails<std::length_error>([]{
        (void)iq_expert_offsets((std::numeric_limits<size_t>::max)(), 680, 2560, 640);
    }));
    assert(fails<std::length_error>([]{
        (void)iq_expert_offsets(1, (std::numeric_limits<size_t>::max)(), 2560, 640);
    }));

    assert(iq_expert_scratch_bytes_checked(80, 640) == 672000);
    assert(iq_expert_scratch_bytes_checked(1, 32) == 3 * 256 + 256);
    assert(fails<std::invalid_argument>([]{ (void)iq_expert_scratch_bytes_checked(0, 640); }));
    assert(fails<std::invalid_argument>([]{ (void)iq_expert_scratch_bytes_checked(1, 641); }));
    assert(fails<std::invalid_argument>([]{ (void)iq_expert_scratch_bytes_checked(INT64_MAX, 640); }));
    assert(fails<std::length_error>([]{ (void)iq_safe_mul(2, (std::numeric_limits<size_t>::max)()); }));
    assert(fails<std::length_error>([]{ (void)iq_safe_add(1, (std::numeric_limits<size_t>::max)()); }));
    assert(fails<std::length_error>([]{ (void)iq_align_256((std::numeric_limits<size_t>::max)()); }));
    return 0;
}
