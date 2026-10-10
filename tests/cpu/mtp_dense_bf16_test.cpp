// Offline regression for native BF16/Q8_0 MTP dense weights (no CUDA required).
#include "strata/core/mtp_manifest.hpp"
#include <cassert>
#include <sstream>
#include <string>
#include <vector>

using strata::core::MtpDenseEntry;

std::string manifest(bool all_bf16) {
    const struct Spec { const char* name; uint64_t rows, cols; } specs[] = {
        {"fc_embedding.weight",64,64}, {"fc_hidden.weight",64,64},
        {"self_attn.q_proj.weight",128,64}, {"self_attn.k_proj.weight",32,64},
        {"self_attn.v_proj.weight",32,64}, {"self_attn.o_proj.weight",64,64},
        {"mlp.shared_expert.gate_proj.weight",32,64},
        {"mlp.shared_expert.up_proj.weight",32,64},
        {"mlp.shared_expert.down_proj.weight",64,32}
    };
    std::string text;
    uint64_t offset = 0;
    for (size_t i = 0; i < 9; ++i) {
        const bool bf16 = all_bf16 || i % 2;
        const uint64_t bytes = specs[i].rows * specs[i].cols * (bf16 ? 2u : 34u) / (bf16 ? 1u : 32u);
        text += std::string(specs[i].name) + (bf16 ? " bf16 " : " q8_0 ") +
                std::to_string(specs[i].rows) + " " + std::to_string(specs[i].cols) + " " +
                std::to_string(offset) + " " + std::to_string(bytes) + "\n";
        offset = (offset + bytes + 255u) & ~255u;
    }
    return text;
}

static bool parse(const std::string& s, int64_t hidden=64, int64_t heads=2, int64_t kv=1, int64_t head_dim=32, int64_t ff=32) {
    std::istringstream in(s);
    std::vector<MtpDenseEntry> entries;
    std::string error;
    if (!strata::core::mtp_dense_index(in, 9999999, entries, error)) return false;
    return strata::core::mtp_projection_geometry(entries, hidden, heads, kv, head_dim, ff, error);
}

int main() {
    assert(parse(manifest(true)));   // all source BF16 bits preserved
    assert(parse(manifest(false)));  // mixed BF16 / Q8_0 site-specific dispatch
    assert(!parse(manifest(true), 32));
    assert(!parse(manifest(false), 64, 3));
    assert(!parse(manifest(true), 64, 2, 2));
    assert(!parse(manifest(true), 64, 2, 1, 64));
    assert(!parse(manifest(true), 64, 2, 1, 32, 64));
    assert(!parse(manifest(true) + "fc_hidden.weight bf16 1 1 999936 2\n"));
    assert(!parse(manifest(false) + "outside.txt q8_0 1 31 999936 34\n"));
    assert(!parse(manifest(false), 64, INT64_MAX, 1, INT64_MAX, 32));
    return 0;
}
