#include "strata/core/mtp_load_safety.hpp"
#include "strata/kernels/mtp_native_launch_shape.hpp"
#include <cassert>
#include <cstdint>
#include <cstring>
#include <stdexcept>

using strata::core::MtpScopedKvMode;
using strata::core::mtp_mapped_allocation;
using strata::kernels::mtp_native_launch_shape;

static bool g_int8 = false, g_hybrid = false;
static void set_int8(bool b) { g_int8 = b; }
static void set_hybrid(bool b) { g_hybrid = b; }

static bool draft(bool original_int8, bool original_hybrid, int failure_mode) {
    g_int8 = original_int8;
    g_hybrid = original_hybrid;
    try {
        MtpScopedKvMode mode(g_int8, g_hybrid, set_int8, set_hybrid);
        assert(!g_hybrid);
        assert(g_int8 == (original_int8 || original_hybrid));
        if (failure_mode == 1) return false;     // cudaMalloc / qsa_state_init failure
        if (failure_mode == 2) throw std::runtime_error("injected error");
    } catch (const std::runtime_error&) {
        assert(failure_mode == 2);
    }
    assert(g_int8 == original_int8 && g_hybrid == original_hybrid);
    return true;
}

struct FakeCuda {
    bool allocation_failure = false;
    bool leave_allocation_on_failure = false;
    bool alias_failure = false;
    bool null_alias = false;
    int allocs = 0, frees = 0;
    uint8_t data[64]{};

    int alloc(void** out, size_t n) {
        assert(n == 32);
        if (allocation_failure && !leave_allocation_on_failure) return 1;
        *out = data;
        ++allocs;
        std::memset(data, 0xab, sizeof(data));
        return allocation_failure ? 1 : 0;
    }
    int alias(void** out, void* host) {
        assert(host == data);
        if (alias_failure) { *out = (void*) uintptr_t(0x55); return 1; }
        if (!null_alias) *out = data + 1;
        return 0;
    }
    void release(void* p) { assert(p == data); ++frees; }
    bool run(void** host, void** device, size_t n = 32) {
        return mtp_mapped_allocation(n, host, device,
            [&](void** p, size_t sz) { return alloc(p, sz); },
            [&](void** d, void* h) { return alias(d, h); },
            [&](void* h) { release(h); });
    }
};

int main() {
    for (int a = 0; a <= 1; ++a)
        for (int b = 0; b <= 1; ++b)
            for (int failure = 0; failure <= 2; ++failure) {
                if (failure == 1) { // ensure destructor still restores on early return
                    g_int8 = a; g_hybrid = b;
                    auto run = [&] {
                        MtpScopedKvMode guard(g_int8, g_hybrid, set_int8, set_hybrid);
                        return false;
                    };
                    assert(!run());
                    assert(g_int8 == bool(a) && g_hybrid == bool(b));
                } else assert(draft(bool(a), bool(b), failure));
            }
    // success zeroes host buffer, points device to mapped alias, retains host ownership
    {
        FakeCuda f;
        void* host = nullptr; void* dev = nullptr;
        assert(f.run(&host, &dev));
        assert(host == f.data && dev == f.data + 1 && f.frees == 0);
        for (size_t i = 0; i < 32; ++i) assert(f.data[i] == 0);
    }
    for (int fault = 0; fault < 4; ++fault) {
        FakeCuda f;
        f.allocation_failure = fault == 0 || fault == 1;
        f.leave_allocation_on_failure = fault == 1;
        f.alias_failure = fault == 2;
        f.null_alias = fault == 3;
        void* host = (void*) uintptr_t(0x1212);
        void* dev = (void*) uintptr_t(0x3434);
        assert(!f.run(&host, &dev));
        assert(host == (void*) uintptr_t(0x1212));
        assert(dev == (void*) uintptr_t(0x3434));
        assert(f.allocs == f.frees);
    }
    {
        FakeCuda f;
        void* host = nullptr, *dev = nullptr;
        assert(!f.run(&host, &dev, 0));
        assert(!f.run(nullptr, &dev));
        assert(!f.run(&host, nullptr));
        assert(f.allocs == 0);
    }
    static_assert(mtp_native_launch_shape(10, 10, 512, 2560, 1536, 8, 30));
    static_assert(mtp_native_launch_shape(20, 10, 512, 2560, 1536, 30, 8));
    static_assert(!mtp_native_launch_shape(11, 10, 512, 2560, 1536, 8, 8));
    static_assert(!mtp_native_launch_shape(128, 1, 512, 2560, 33554432, 8, 8));
    static_assert(!mtp_native_launch_shape(10, 0, 512, 2560, 1536, 8, 8));
    static_assert(!mtp_native_launch_shape(10, 11, 512, 2560, 1536, 8, 8));
    static_assert(!mtp_native_launch_shape(10, 10, 0, 2560, 1536, 8, 8));
    static_assert(!mtp_native_launch_shape(10, 10, 512, 2561, 1536, 8, 8));
    static_assert(!mtp_native_launch_shape(10, 10, 512, 2560, 1537, 8, 8));
    static_assert(!mtp_native_launch_shape(10, 10, 512, 2560, 1536, 14, 8));
}
