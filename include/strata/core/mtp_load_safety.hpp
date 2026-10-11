#pragma once

#include <cstddef>
#include <cstring>

namespace strata::core {

// The QSA KV flags are process-wide. A failed MTP draft-cache allocation must
// never leave the main model in the draft layer's temporary KV format.
class MtpScopedKvMode {
public:
    using Setter = void (*)(bool);

    MtpScopedKvMode(bool previous_int8, bool previous_hybrid,
                    Setter set_int8, Setter set_hybrid) noexcept
        : previous_int8_(previous_int8), previous_hybrid_(previous_hybrid),
          set_int8_(set_int8), set_hybrid_(set_hybrid) {
        set_hybrid_(false);
        if (previous_hybrid_) set_int8_(true); // k8v4 draft uses plain int8
    }

    ~MtpScopedKvMode() noexcept {
        set_int8_(previous_int8_);
        set_hybrid_(previous_hybrid_);
    }

    MtpScopedKvMode(const MtpScopedKvMode&) = delete;
    MtpScopedKvMode& operator=(const MtpScopedKvMode&) = delete;
    MtpScopedKvMode(MtpScopedKvMode&&) = delete;
    MtpScopedKvMode& operator=(MtpScopedKvMode&&) = delete;

private:
    bool previous_int8_, previous_hybrid_;
    Setter set_int8_, set_hybrid_;
};

// No CUDA dependency: test with allocation/alias errors independently of a GPU.
// Both output pointers are published atomically only when all steps succeed.
// In particular, an alias failure must release pinned host memory immediately.
template <class Allocate, class Alias, class Release>
bool mtp_mapped_allocation(std::size_t bytes, void** host, void** device,
                           Allocate allocate, Alias alias, Release release) {
    if (bytes == 0 || !host || !device) return false;
    void* candidate_host = nullptr;
    if (allocate(&candidate_host, bytes) != 0 || candidate_host == nullptr) {
        if (candidate_host) release(candidate_host); // defensive partial allocation
        return false;
    }
    void* candidate_device = nullptr;
    if (alias(&candidate_device, candidate_host) != 0 || !candidate_device) {
        release(candidate_host);
        return false;
    }
    std::memset(candidate_host, 0, bytes);
    *host = candidate_host;
    *device = candidate_device;
    return true;
}

} // namespace strata::core
