// Off-line safety tests: exactly the MTP runtime dense.txt format, no CUDA/model data.
#include "strata/core/mtp_manifest.hpp"
#include <cassert>
#include <sstream>
#include <string>
#include <vector>

static constexpr const char* required[] = {
    "fc_embedding.weight", "fc_hidden.weight", "self_attn.q_proj.weight", "self_attn.k_proj.weight",
    "self_attn.v_proj.weight", "self_attn.o_proj.weight", "mlp.shared_expert.gate_proj.weight",
    "mlp.shared_expert.up_proj.weight", "mlp.shared_expert.down_proj.weight"
};

std::string valid_index() {
    std::string text;
    uint64_t offset = 0;
    for (auto name : required) {
        text += std::string(name) + " q8_0 2 32 " + std::to_string(offset) + " 68\n";
        offset += 256;
    }
    text += "norm.weight f32 1 4 2304 16\n";
    return text;
}

bool accepted(const std::string& s, uint64_t length = 4096) {
    std::istringstream input(s);
    std::vector<strata::core::MtpDenseEntry> entries;
    std::string error;
    return strata::core::mtp_dense_index(input, length, entries, error);
}

int main() {
    const std::string good = valid_index();
    assert(accepted(good));
    assert(!accepted(""));
    assert(!accepted(good.substr(0, good.find('\n'))));              // missing projections
    assert(!accepted(good + "fc_embedding.weight q8_0 2 32 2560 68\n")); // duplicate tensor
    assert(!accepted(good + "junk f16 1 1 2560 2\n"));              // unsupported type
    assert(!accepted(good + "junk bf16 1 1 5000 2\n"));            // beyond EOF
    assert(!accepted(good + "junk bf16 1 1 0 2\n"));               // overlapping
    assert(!accepted(good + "junk bf16 1 1 2305 2\n"));            // misaligned
    assert(!accepted(good + "junk bf16 -1 1 2560 2\n"));           // signed dimensions
    assert(!accepted(good + "junk bf16 1 1 2560 999999\n"));       // wrong bytes
    assert(!accepted(good + "junk q8_0 1 31 2560 34\n"));          // non-block geometry
    assert(!accepted(good + "junk bf16 18446744073709551615 2 2560 2\n")); // overflow
    assert(!accepted(good + "junk bf16 1 1 2560 2 garbage\n"));    // trailing garbage
    assert(!accepted(good, 2200));                                   // existing projected data outside EOF
    assert(!accepted(good + "junk f32 1 1 2560 4\n" + "junk2 f32 1 1 2560 4\n")); // overlap
    return 0;
}
