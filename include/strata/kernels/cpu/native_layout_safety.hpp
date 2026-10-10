// Checked arithmetic and shard-name contract for native_experts.txt (GGUF v3/v4).
// Header-only so the same rules can be tested without ggml, CUDA or the model weights.
#pragma once

#include <cstdint>
#include <limits>
#include <string_view>

namespace strata::kernels::cpu {

inline bool native_layout_add(uint64_t at, uint64_t bytes_per_expert, uint64_t experts,
                              uint64_t& next) noexcept {
    if (experts == 0 || bytes_per_expert == 0 ||
        bytes_per_expert > (std::numeric_limits<uint64_t>::max() - at) / experts) return false;
    next = at + bytes_per_expert * experts;
    return true;
}

inline bool native_role_fits(uint64_t offset, uint64_t bytes_per_expert, uint64_t experts,
                             uint64_t file_bytes) noexcept {
    uint64_t end = 0;
    return offset <= file_bytes && native_layout_add(offset, bytes_per_expert, experts, end) &&
           end <= file_bytes;
}

// Empty means the first --native GGUF shard. Other entries MUST be names within its directory;
// never resolve an absolute path or traverse the filesystem via an untrusted pack manifest.
inline bool native_shard_name_ok(std::string_view s) noexcept {
    if (s.empty()) return true;
    if (s.size() > 255 || s == "." || s == ".." || s[0] == '.') return false;
    for (unsigned char c : s) {
        if (c < 0x20 || c == 0x7f || c == '/' || c == '\\' || c == ':' || c == '<' ||
            c == '>' || c == '|' || c == '"' || c == '*' || c == '?') return false;
    }
    if (s.size() < 6) return false;
    const auto suffix = s.substr(s.size() - 5);
    return suffix == ".gguf" || suffix == ".GGUF";
}

}  // namespace strata::kernels::cpu
