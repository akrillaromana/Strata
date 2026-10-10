#include "strata/kernels/ple_bounds.hpp"

#include <cstdint>
#include <cstdio>
#include <limits>

using strata::kernels::ple_table_fits;

static_assert(ple_table_fits(202, 32, 0, 1, 170, true));
static_assert(ple_table_fits(202, 32, 0, 1, 170, false));
static_assert(!ple_table_fits(201, 32, 0, 1, 170, true));
static_assert(!ple_table_fits(203, 32, 0, 1, 170, true));
static_assert(ple_table_fits(400, 32, 128, 1, 170, false));
static_assert(!ple_table_fits(400, 32, 128, 1, 170, true));
static_assert(!ple_table_fits(400, 32, 200, 1, 170, false));
static_assert(!ple_table_fits(400, 401, 0, 1, 170, false));
static_assert(!ple_table_fits(400, 32, 0, 0, 170, false));
static_assert(!ple_table_fits(400, 32, 0, 1, 0, false));
static_assert(!ple_table_fits(std::numeric_limits<uint64_t>::max(), 0, 0,
                              std::numeric_limits<uint64_t>::max(), 170, false));
static_assert(!ple_table_fits(std::numeric_limits<uint64_t>::max(), 0,
                              std::numeric_limits<uint64_t>::max() - 2, 1, 170, false));

int main() {
    struct Case {
        uint64_t size, start, offset, rows, bytes;
        bool alone, expected;
    };
    constexpr Case cases[] = {
        {202, 32, 0, 1, 170, true, true},
        {400, 32, 128, 1, 170, false, true},
        {201, 32, 0, 1, 170, true, false},
        {203, 32, 0, 1, 170, true, false},
        {400, 32, 200, 1, 170, false, false},
        {400, 401, 0, 1, 170, false, false},
        {std::numeric_limits<uint64_t>::max(), 0, 0,
         std::numeric_limits<uint64_t>::max(), 170, false, false},
    };
    for (const auto& c : cases) {
        if (ple_table_fits(c.size, c.start, c.offset, c.rows, c.bytes, c.alone) != c.expected) {
            std::fprintf(stderr, "PLE tensor size validation failed\n");
            return 1;
        }
    }
    return 0;
}
