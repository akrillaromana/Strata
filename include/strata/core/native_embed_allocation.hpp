#pragma once

// A CUDA/HIP-independent transaction for embedding table storage.  The device
// address can either alias pinned host memory or own a separate GPU allocation.
// A partially failed load must not leak allocations or publish an unusable
// device pointer to NativeEmbed. Release callbacks are supplied by the caller
// so that this contract can be tested on a CPU without CUDA libraries.

#include <stdexcept>

namespace strata::core {

class NativeEmbedAllocation {
public:
    using Release = void (*)(void*);

    NativeEmbedAllocation(Release release_host, Release release_device)
        : release_host_(release_host), release_device_(release_device) {
        if (!release_host_ || !release_device_)
            throw std::invalid_argument("native embedding: missing storage release callback");
    }
    ~NativeEmbedAllocation() { reset(); }

    NativeEmbedAllocation(const NativeEmbedAllocation&) = delete;
    NativeEmbedAllocation& operator=(const NativeEmbedAllocation&) = delete;

    void set_host(void* p) {
        if (!p || host_) throw std::logic_error("native embedding: duplicate/null pinned storage");
        host_ = p;
    }
    void set_device_alias(void* p) {
        if (!host_ || !p || device_)
            throw std::logic_error("native embedding: invalid pinned device alias");
        device_ = p;
        device_owned_ = false;
    }
    void set_device_owned(void* p) {
        if (!p || device_)
            throw std::logic_error("native embedding: duplicate/null device storage");
        device_ = p;
        device_owned_ = true;
    }
    void drop_host_after_copy() noexcept {
        if (host_) release_host_(host_);
        host_ = nullptr;
        // A device alias is only valid for the lifetime of its host allocation.
        if (!device_owned_) device_ = nullptr;
    }
    void commit(void*& host, const void*& device) {
        if (!device_) throw std::logic_error("native embedding: no device pointer to commit");
        host = host_;
        device = device_;
        host_ = nullptr;
        device_ = nullptr;
        device_owned_ = false;
    }
    void reset() noexcept {
        if (device_owned_ && device_) release_device_(device_);
        if (host_) release_host_(host_);
        device_ = nullptr;
        host_ = nullptr;
        device_owned_ = false;
    }

private:
    Release release_host_;
    Release release_device_;
    void* host_ = nullptr;
    void* device_ = nullptr;
    bool device_owned_ = false;
};

} // namespace strata::core
