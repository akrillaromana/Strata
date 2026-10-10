// Iteration 024: CUDA/HIP embedding storage transactional lifetime.
// Uses fake addresses and callbacks; safe to run without a GPU or CUDA libs.
#include "strata/core/native_embed_allocation.hpp"

#include <cassert>
#include <stdexcept>

namespace {
int host_releases = 0;
int device_releases = 0;
int host_address = 1;
int gpu_address = 2;
int alias_address = 3;
void free_host(void* p) { assert(p == &host_address); ++host_releases; }
void free_device(void* p) { assert(p == &gpu_address); ++device_releases; }
void reset() { host_releases = device_releases = 0; }
}

int main() {
    using strata::core::NativeEmbedAllocation;
    // Successfully mapped host memory: alias is NOT an independently owned GPU pointer.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        txn.set_host(&host_address);
        txn.set_device_alias(&alias_address);
        void* owner_host = nullptr;
        const void* owner_device = nullptr;
        txn.commit(owner_host, owner_device);
        assert(owner_host == &host_address && owner_device == &alias_address);
        assert(host_releases == 0 && device_releases == 0);
        free_host(owner_host); // models NativeEmbed destructor on success
    }
    assert(host_releases == 1 && device_releases == 0);

    // Error after mapping, before publication: only host memory is released.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        txn.set_host(&host_address);
        txn.set_device_alias(&alias_address);
    }
    assert(host_releases == 1 && device_releases == 0);

    // VRAM fallback after mapping failure: host freed immediately; GPU on failure.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        txn.set_host(&host_address);
        txn.set_device_owned(&gpu_address);
        txn.drop_host_after_copy();
        assert(host_releases == 1 && device_releases == 0);
        // Simulate later error before publish.
    }
    assert(host_releases == 1 && device_releases == 1);

    // Successful VRAM-only fallback: ownership moves to NativeEmbed.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        txn.set_device_owned(&gpu_address);
        void* h = nullptr;
        const void* d = nullptr;
        txn.commit(h, d);
        assert(h == nullptr && d == &gpu_address);
        free_device(const_cast<void*>(d));
    }
    assert(host_releases == 0 && device_releases == 1);

    // Midway copy failure: pinned and GPU storage must both be released.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        txn.set_host(&host_address);
        txn.set_device_owned(&gpu_address);
    }
    assert(host_releases == 1 && device_releases == 1);

    // An alias must never survive the end of its pinned host allocation.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        txn.set_host(&host_address);
        txn.set_device_alias(&alias_address);
        txn.drop_host_after_copy();
        void* h = nullptr;
        const void* d = nullptr;
        bool rejected = false;
        try { txn.commit(h, d); } catch (const std::logic_error&) { rejected = true; }
        assert(rejected && h == nullptr && d == nullptr);
    }
    assert(host_releases == 1 && device_releases == 0);

    // Bad usage cannot silently publish a null/duplicate pointer.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        bool rejected = false;
        try { txn.set_device_alias(&alias_address); } catch (const std::logic_error&) { rejected = true; }
        assert(rejected);
        txn.set_host(&host_address);
        rejected = false;
        try { txn.set_host(&host_address); } catch (const std::logic_error&) { rejected = true; }
        assert(rejected);
    }
    assert(host_releases == 1 && device_releases == 0);

    // The recovery path can publish a GPU allocation after losing pinned host.
    reset();
    {
        NativeEmbedAllocation txn(free_host, free_device);
        txn.set_host(&host_address);
        txn.set_device_owned(&gpu_address);
        txn.drop_host_after_copy();
        void* h = nullptr;
        const void* d = nullptr;
        txn.commit(h, d);
        assert(h == nullptr && d == &gpu_address);
        free_device(const_cast<void*>(d));
    }
    assert(host_releases == 1 && device_releases == 1);
}
