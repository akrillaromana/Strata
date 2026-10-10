#pragma once

#include <cstdint>
#include <limits>

namespace strata::kernels {

// Header-only arithmetic gate for a disk-backed PLE tensor. Validates every
// addition/multiplication BEFORE a mapped pointer or Direct-IO offset is used.
// The tensor offset is relative to the GGUF data section, not to the file.
// A single-tensor shard must contain exactly that tensor, with no padding gap
// or unexpected appended bytes; multi-tensor shards may contain other data.
constexpr bool ple_table_fits(uint64_t file_bytes, uint64_t data_start,
                              uint64_t tensor_offset, uint64_t row_count,
                              uint64_t row_bytes, bool single_tensor) noexcept {
    if (row_bytes == 0 || row_count == 0 || data_start > file_bytes) return false;
    if (row_count > std::numeric_limits<uint64_t>::max() / row_bytes) return false;
    const uint64_t table_bytes = row_count * row_bytes;
    const uint64_t data_bytes = file_bytes - data_start;
    if (tensor_offset > data_bytes || table_bytes > data_bytes - tensor_offset) return false;
    if (single_tensor && (tensor_offset != 0 || table_bytes != data_bytes)) return false;
    return true;
}

}  // namespace strata::kernels
