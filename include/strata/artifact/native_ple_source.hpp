// Native GGUF PLE provenance contract. A requested Q8_0 n-gram table must
// physically be a shard of the --native model (not another file with matching
// quantization/shape). Header and tensor boundary checks remain in GgufModel.
#pragma once

#include <cstddef>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

namespace strata {

inline bool native_ple_is_original_shard(const std::vector<std::string>& native_shards,
                                         size_t owner_index, const std::string& selected_ple) {
    if (owner_index >= native_shards.size()) return false;
    if (selected_ple.empty()) return true;  // caller will select the known model shard
    std::error_code ec;
    const bool equivalent = std::filesystem::equivalent(
        std::filesystem::path(selected_ple), std::filesystem::path(native_shards[owner_index]), ec);
    return !ec && equivalent;
}

}  // namespace strata
