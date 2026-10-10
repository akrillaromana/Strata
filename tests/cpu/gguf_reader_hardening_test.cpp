// CPU-only GGUF negative cases for native Unsloth Q6_K / Huihui Q8_0 split loading.
// No model files or GPU are required.
#include "strata/artifact/gguf_reader.hpp"
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
template<class T> void put(std::vector<uint8_t>& b, T v) {
    const auto i = b.size(); b.resize(i + sizeof(T));
    std::memcpy(b.data() + i, &v, sizeof(T));
}
void str(std::vector<uint8_t>& b, const std::string& s) {
    put<uint64_t>(b, s.size()); b.insert(b.end(), s.begin(), s.end());
}
struct K { std::string name; uint32_t kind; uint64_t number; std::string value; };
K uintkv(std::string k, uint64_t v) { return {std::move(k), 4, v, {}}; }
K u16kv(std::string k, uint64_t v) { return {std::move(k), 2, v, {}}; }
K skv(std::string k, std::string v) { return {std::move(k), 8, 0, std::move(v)}; }
void write_file(const std::filesystem::path& p, const std::vector<K>& kv, int type, bool corrupt_count=false) {
    std::vector<uint8_t> b;
    put<uint32_t>(b, 0x46554747u); put<uint32_t>(b, 3);
    put<uint64_t>(b, corrupt_count ? std::numeric_limits<uint64_t>::max() : 1);
    put<uint64_t>(b, kv.size());
    for (const auto& k : kv) {
        str(b, k.name); put<uint32_t>(b, k.kind);
        if (k.kind == 8) str(b, k.value);
        else if (k.kind == 4) put<uint32_t>(b, uint32_t(k.number));
        else if (k.kind == 2) put<uint16_t>(b, uint16_t(k.number));
        else throw std::runtime_error("test bug");
    }
    str(b, type == 14 ? "blk.0.attn_q.weight" : "blk.1.attn_q.weight"); put<uint32_t>(b, 1);
    put<uint64_t>(b, type == 14 ? 256 : 32);
    put<uint32_t>(b, type); put<uint64_t>(b, 0);
    b.resize((b.size() + 31) / 32 * 32 + (type == 14 ? 210 : 34), 0);
    std::ofstream f(p, std::ios::binary);
    f.write(reinterpret_cast<const char*>(b.data()), (std::streamsize)b.size());
}
void expect_failure(const std::function<void()>& callback) {
    bool rejected = false;
    try { callback(); } catch (const std::exception&) { rejected = true; }
    assert(rejected && "corrupted GGUF was accepted");
}
}
int main() {
    namespace fs = std::filesystem;
    const fs::path dir = fs::temp_directory_path() /
        ("strata-gguf021-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directory(dir);
    const fs::path a = dir / "Unsloth-Q6_K-00001-of-00002.gguf";
    const fs::path b = dir / "Unsloth-Q6_K-00002-of-00002.gguf";
    const std::vector<K> first = {skv("general.architecture", "qwen4exp"), uintkv("split.count", 2),
                                  uintkv("split.no", 0), uintkv("split.tensors.count", 2)};
    const std::vector<K> second = {skv("general.architecture", "qwen4exp"), uintkv("split.count", 2),
                                   uintkv("split.no", 1), uintkv("split.tensors.count", 2)};
    auto open = [&]() { return strata::GgufModel(std::vector<std::string>{a.string(), b.string()}); };
    write_file(a, first, 14); write_file(b, second, 8);
    {
        auto m = open();
        assert(m.size() == 2 && m.in_bounds(m.shard(0).tensors().at(0), 0));
        assert(m.in_bounds(m.shard(1).tensors().at(0), 1));
        assert(m.shard(0).tensors()[0].type == 14 && m.shard(1).tensors()[0].type == 8);
    }
    // GGUF shard keys emitted by llama.cpp can be UINT16, not only UINT32.
    write_file(a, {skv("general.architecture", "qwen4exp"), u16kv("split.count", 2),
                   u16kv("split.no", 0), uintkv("split.tensors.count", 2)}, 14);
    write_file(b, {skv("general.architecture", "qwen4exp"), u16kv("split.count", 2),
                   u16kv("split.no", 1), uintkv("split.tensors.count", 2)}, 8);
    { auto m = open(); assert(m.size() == 2); }
    write_file(a, first, 14);
    write_file(b, second, 8);
    expect_failure([&] { (void)strata::GgufModel({a.string()}); }); // missing family
    write_file(b, {skv("general.architecture", "other"), uintkv("split.count", 2),
                   uintkv("split.no", 1), uintkv("split.tensors.count", 2)}, 8);
    expect_failure([&] { (void)open(); }); // conflicting Huihui metadata
    write_file(b, {skv("general.architecture", "qwen4exp"), uintkv("split.count", 2),
                   uintkv("split.no", 1), uintkv("split.tensors.count", 3)}, 8);
    expect_failure([&] { (void)open(); }); // count disagreement
    write_file(b, {skv("general.architecture", "qwen4exp"), uintkv("split.count", 2),
                   uintkv("split.no", 1), uintkv("split.tensors.count", 7)}, 8);
    expect_failure([&] { (void)open(); }); // malformed total
    write_file(b, {skv("general.architecture", "qwen4exp"), uintkv("split.count", 2),
                   uintkv("split.no", 1), skv("split.tensors.count", "2")}, 8);
    expect_failure([&] { (void)open(); }); // wrong metadata VALUE TYPE
    write_file(b, second, 8);
    write_file(a, {skv("general.architecture", "qwen4exp"), uintkv("split.count", 2),
                   uintkv("split.count", 2), uintkv("split.no", 0), uintkv("split.tensors.count", 2)}, 14);
    expect_failure([&] { strata::GgufFile g(a.string()); }); // duplicate key
    write_file(a, {uintkv("general.alignment", 3)}, 14);
    expect_failure([&] { strata::GgufFile g(a.string()); }); // non-power-of-two alignment
    write_file(a, {skv("general.alignment", "32")}, 14);
    expect_failure([&] { strata::GgufFile g(a.string()); }); // wrong alignment type
    write_file(a, {}, 14, true);
    expect_failure([&] { strata::GgufFile g(a.string()); }); // huge tensor count
    {
        std::vector<uint8_t> bytes;
        put<uint32_t>(bytes, 0x46554747u); put<uint32_t>(bytes, 3);
        put<uint64_t>(bytes, 0); put<uint64_t>(bytes, 1);
        put<uint64_t>(bytes, std::numeric_limits<uint64_t>::max());
        std::ofstream f(a, std::ios::binary);
        f.write(reinterpret_cast<const char*>(bytes.data()), (std::streamsize)bytes.size());
    }
    expect_failure([&] { strata::GgufFile g(a.string()); }); // u64 string length
    std::ofstream(a, std::ios::binary | std::ios::trunc).close();
    expect_failure([&] { strata::GgufFile g(a.string()); }); // zero-length mmap
    fs::remove_all(dir);
    return 0;
}
