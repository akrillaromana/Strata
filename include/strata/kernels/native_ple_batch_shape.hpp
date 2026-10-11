#pragma once

// Host-only preflight shared by CUDA/HIP and the experimental SYCL backend.
// No GPU headers: failures can be exercised before submitting any kernel.
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace strata::kernels {

struct NativePleBatchShape {
    unsigned rows;
    unsigned blocks;
    std::size_t key_bytes;
    std::size_t value_bytes;
    std::size_t gate_bytes;
};

inline NativePleBatchShape native_ple_batch_shape(int tokens) {
    constexpr std::uint64_t hidden = 10240, embedding = 2560, groups = 4;
    constexpr std::uint64_t threads = 256;
    if (tokens <= 0) throw std::invalid_argument("native PLE batch requires tokens > 0");
    const auto t = static_cast<std::uint64_t>(tokens);
    const std::uint64_t elements = t * hidden;
    const std::uint64_t rows = t * groups;
    const std::uint64_t blocks = (elements + threads - 1) / threads;
    const std::uint64_t key_bytes = elements * sizeof(float);
    const std::uint64_t val_bytes = t * embedding * sizeof(float);
    const std::uint64_t gate_bytes = rows * sizeof(float);
    if (rows > static_cast<std::uint64_t>(std::numeric_limits<int>::max()) ||
        blocks > static_cast<std::uint64_t>(std::numeric_limits<int>::max()) ||
        key_bytes > std::numeric_limits<std::size_t>::max() ||
        val_bytes > std::numeric_limits<std::size_t>::max() ||
        gate_bytes > std::numeric_limits<std::size_t>::max())
        throw std::length_error("native PLE batch launch dimensions overflow");
    return {static_cast<unsigned>(rows), static_cast<unsigned>(blocks),
            static_cast<std::size_t>(key_bytes), static_cast<std::size_t>(val_bytes),
            static_cast<std::size_t>(gate_bytes)};
}

struct NativePleBatchSpan {
    const void* ptr;
    std::size_t bytes;
    std::size_t alignment = alignof(float);
};

inline void native_ple_batch_nonoverlap(const NativePleBatchSpan* spans,
                                        std::size_t count) {
    for (std::size_t i = 0; i < count; ++i) {
        const auto start = reinterpret_cast<std::uintptr_t>(spans[i].ptr);
        if (!start || !spans[i].alignment ||
            (spans[i].alignment & (spans[i].alignment - 1)) ||
            (start & (spans[i].alignment - 1)) ||
            spans[i].bytes > std::numeric_limits<std::uintptr_t>::max() - start)
            throw std::invalid_argument("native PLE batch: null, unaligned or overflowing span");
        const auto end = start + spans[i].bytes;
        for (std::size_t j = 0; j < i; ++j) {
            const auto prior = reinterpret_cast<std::uintptr_t>(spans[j].ptr);
            if (start < prior + spans[j].bytes && prior < end)
                throw std::invalid_argument("native PLE batch: buffers overlap");
        }
    }
}
} // namespace strata::kernels
