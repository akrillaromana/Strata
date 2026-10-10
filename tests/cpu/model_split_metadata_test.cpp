// Source-only multi-shard GGUF metadata contract; no weights, CUDA or GPU.
#include "strata/artifact/gguf_reader.hpp"
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace {
template<typename T> void put(std::vector<uint8_t>& b, T v) {
    auto n = b.size(); b.resize(n + sizeof(T));
    std::memcpy(b.data() + n, &v, sizeof(T));
}
void str(std::vector<uint8_t>& b, const std::string& s) {
    put<uint64_t>(b, s.size()); b.insert(b.end(), s.begin(), s.end());
}
void u32(std::vector<uint8_t>& b, const std::string& key, uint32_t v) {
    str(b, key); put<uint32_t>(b, 4); put<uint32_t>(b, v);
}
void s8(std::vector<uint8_t>& b, const std::string& key, const std::string& v) {
    str(b, key); put<uint32_t>(b, 8); str(b, v);
}
void shard(const std::filesystem::path& p, int which, const std::string& arch,
           int total_which, bool include_total) {
    std::vector<uint8_t> b;
    put<uint32_t>(b, 0x46554747u); put<uint32_t>(b, 3);
    put<uint64_t>(b, 1); // tensor count
    put<uint64_t>(b, 2 + (arch.empty() ? 0 : 1) + (include_total ? 1 : 0));
    u32(b, "split.no", which); u32(b, "split.count", 2);
    if (include_total) u32(b, "split.tensors.count", total_which);
    if (!arch.empty()) s8(b, "general.architecture", arch);
    str(b, "blk." + std::to_string(which) + ".attn_q.weight");
    put<uint32_t>(b, 1); put<uint64_t>(b, 8); // 1 dimension, 8 elements
    put<uint32_t>(b, 0); put<uint64_t>(b, 0); // F32, offset zero
    b.resize((b.size() + 31) / 32 * 32 + 32, 0);
    std::ofstream f(p, std::ios::binary); f.write((char*)b.data(), (std::streamsize)b.size());
}
}
int main() {
    namespace fs = std::filesystem;
    const fs::path dir = fs::temp_directory_path() /
        ("strata-model-variants-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directory(dir);
    const auto a = dir / "Huihui-Qwen3.8-Flash-Next-Q8_0-00001-of-00002.gguf";
    const auto b = dir / "Huihui-Qwen3.8-Flash-Next-Q8_0-00002-of-00002.gguf";
    auto opens = [&]() {
        auto model = strata::GgufModel::open(a.string());
        return model.size() == 2 && model.find("blk.1.attn_q.weight") != nullptr;
    };
    shard(a, 0, "qwen4exp", 2, true);
    shard(b, 1, "qwen4exp", 2, true); // re-split Huihui may repeat arch
    assert(opens());
    shard(b, 1, "other-architecture", 2, true);
    try { (void)opens(); assert(false && "conflicting architecture accepted"); }
    catch (const std::runtime_error&) {}
    shard(b, 1, "", 3, true);
    try { (void)opens(); assert(false && "conflicting tensor total accepted"); }
    catch (const std::runtime_error&) {}
    shard(a, 0, "qwen4exp", 2, false);
    shard(b, 1, "", 2, true);
    try { (void)opens(); assert(false && "late-only tensor total accepted"); }
    catch (const std::runtime_error&) {}
    fs::remove(b);
    try { (void)opens(); assert(false && "incomplete shard family accepted"); }
    catch (const std::runtime_error&) {}
    fs::remove_all(dir);
    return 0;
}
