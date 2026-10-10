// Iteration 023: NativeHead and NativeEmbed share a full-source preflight.
// Standalone C++ only; no CUDA, no model weights, no access to user devices.
#include "../core/gguf_fixture.hpp"
#include "strata/artifact/gguf_reader.hpp"

#include <cassert>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
namespace {
struct ScratchDir {
    fs::path path;
    ScratchDir() {
        path = fs::temp_directory_path() /
            ("strata-head-embed-023-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
        fs::create_directories(path);
    }
    ~ScratchDir() { std::error_code ec; fs::remove_all(path, ec); }
};

bool rejects(const std::function<void()>& f, const std::string& word) {
    try { f(); } catch (const std::runtime_error& e) {
        return std::string(e.what()).find(word) != std::string::npos;
    }
    return false;
}

std::vector<std::string> make_shards(const fs::path& root, uint64_t tail_cut = 0) {
    std::vector<std::string> paths;
    for (int i = 0; i < 3; ++i) {
        auto kv = fixture::split_keys(i, 3, 3);
        if (i == 0) kv.push_back(fixture::str("general.architecture", "qwen4exp"));
        std::vector<fixture::Tensor> tensors;
        if (i == 1) tensors = {
            {"output.weight", {256, 2}, 8, 1},
            {"token_embd.weight", {256, 2}, 8, 2}
        };
        if (i == 2) tensors = {{"blk.0.attn_q.weight", {256, 1}, 14, 3}};
        const auto path = root / ("mini-Q6_K-" + std::to_string(i + 1) + ".gguf");
        fixture::write(path, kv, tensors, i == 2 ? tail_cut : 0);
        paths.push_back(path.string());
    }
    return paths;
}
}

int main() {
    ScratchDir tmp;
    const auto shards = make_shards(tmp.path);
    {
        strata::GgufModel model(shards);
        assert(model.size() == 3 && model.shard(0).tensors().empty());
        strata::validate_native_model_payloads(model);
        size_t at = 999;
        const auto* output = model.find("output.weight", &at);
        assert(output && at == 1);
        const auto* emb = model.find("token_embd.weight", &at);
        assert(emb && at == 1);
        assert(strata::native_embedding_checked_bytes(*emb, 256, 2, 272) == 544);
        assert(rejects([&] { (void) strata::native_embedding_checked_bytes(*emb, 256, -2, 272); }, "dimensions"));
        assert(rejects([&] { (void) strata::native_embedding_checked_bytes(*emb, 0, 2, 272); }, "dimensions"));
        assert(rejects([&] { (void) strata::native_embedding_checked_bytes(*emb, 128, 2, 272); }, "dimensions"));
        assert(rejects([&] { (void) strata::native_embedding_checked_bytes(*emb, 256, 3, 272); }, "dimensions"));
        assert(rejects([&] { (void) strata::native_embedding_checked_bytes(*emb, 256, 2, 0); }, "dimensions"));
        assert(rejects([&] { (void) strata::native_embedding_checked_bytes(*emb, 256, 2, 256); }, "geometry"));
        assert(rejects([&] { (void) strata::native_embedding_checked_bytes(*emb, 256, 2,
                          (std::numeric_limits<uint64_t>::max)()); }, "overflow"));
    }
    // Second shard looks valid, but a damaged Q6_K tensor in the last shard
    // MUST refuse NativeHead/NativeEmbed preflight before any CUDA allocation.
    make_shards(tmp.path, 50);
    {
        strata::GgufModel model(shards);
        size_t at = 999;
        assert(model.find("output.weight", &at) && at == 1);
        assert(model.find("token_embd.weight", &at) && at == 1);
        assert(rejects([&] { strata::validate_native_model_payloads(model); }, "truncated tensor payload"));
    }
    {
        // Single-source BF16 embedding GGUF used by the existing pack path.
        const fs::path p = tmp.path / "strata-bf16-embedding.gguf";
        fixture::write(p, {fixture::str("general.architecture", "strata-embd")},
                       {{"token_embd.weight", {256, 2}, 30, 4}});
        const strata::GgufModel model({p.string()});
        strata::validate_native_model_payloads(model);
        const auto* emb = model.find("token_embd.weight");
        assert(emb && strata::native_embedding_checked_bytes(*emb, 256, 2, 512) == 1024);
    }
}
