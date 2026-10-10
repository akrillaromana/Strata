// Strata Custom 022: CPU-only native GGUF directory preflight for Q6_K/Q8_0.
// Does not require CUDA, GGUF weights, or the target user's machine.
#include "strata/artifact/gguf_reader.hpp"
#include <algorithm>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
template <typename T> void put(std::vector<uint8_t>& b, T v) {
    const size_t at = b.size();
    b.resize(at + sizeof(T));
    std::memcpy(b.data() + at, &v, sizeof v);
}
void str(std::vector<uint8_t>& b, const std::string& s) {
    put<uint64_t>(b, s.size());
    b.insert(b.end(), s.begin(), s.end());
}
void create(const std::filesystem::path& p, uint64_t first_width = 256,
            uint64_t second_offset = 448, uint64_t last_bytes = 102,
            uint64_t q6_height = 2, uint32_t q6_type = 14) {
    std::vector<uint8_t> b;
    put<uint32_t>(b, 0x46554747u); put<uint32_t>(b, 3);
    put<uint64_t>(b, 2); put<uint64_t>(b, 0);
    str(b, "blk.0.ffn_gate_shexp.weight");
    put<uint32_t>(b, 2); put<uint64_t>(b, first_width); put<uint64_t>(b, q6_height);
    put<uint32_t>(b, q6_type); put<uint64_t>(b, 0);
    str(b, "blk.0.ffn_up_shexp.weight");
    put<uint32_t>(b, 2); put<uint64_t>(b, 32); put<uint64_t>(b, 3);
    put<uint32_t>(b, 8); put<uint64_t>(b, second_offset);
    b.resize((b.size() + 31) / 32 * 32 + std::max<uint64_t>(420, second_offset + last_bytes));
    std::ofstream o(p, std::ios::binary | std::ios::trunc);
    o.write(reinterpret_cast<const char*>(b.data()), (std::streamsize)b.size());
}
bool rejects(const std::filesystem::path& p, const std::string& expected) {
    try { strata::GgufFile g(p.string()); strata::validate_native_tensor_layout(g); }
    catch (const std::runtime_error& e) { return std::string(e.what()).find(expected) != std::string::npos; }
    return false;
}
}
int main() {
    namespace fs = std::filesystem;
    const auto dir = fs::temp_directory_path() /
        ("strata-native-payload-022-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directory(dir);
    const auto f = dir / "Qwen3.8-Q6_K-Q8_0.gguf";
    create(f);
    {
        strata::GgufFile g(f.string());
        strata::validate_native_tensor_layout(g);
        assert(strata::tensor_payload_bytes(g.tensors()[0]) == 420);
        assert(strata::tensor_payload_bytes(g.tensors()[1]) == 102);
    }
    create(f, 128); // elements are 128*2=256, but each row is only half a Q6_K block
    assert(rejects(f, "block geometry"));
    create(f, 256, 416); // aligned offset; Q6_K spans [0,420), Q8_0 starts at 416
    assert(rejects(f, "overlapping tensor payloads"));
    create(f, 256, 448, 20);
    assert(rejects(f, "truncated tensor payload"));
    create(f, 256, 4);
    assert(rejects(f, "unaligned tensor offset"));
    create(f, 256, 0);
    assert(rejects(f, "overlapping tensor payloads"));
    create(f, 256, 448, 102, std::numeric_limits<uint64_t>::max());
    assert(rejects(f, "block geometry"));
    create(f, 256, 448, 102, 2, 5000);
    assert(rejects(f, "block geometry"));
    fs::remove_all(dir);
}
