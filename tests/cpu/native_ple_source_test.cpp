// Source-only test: Q8 n-gram must come from the native model's actual shard.
// No CUDA, GGUF weights, model execution or networking.
#include "strata/artifact/native_ple_source.hpp"

#include <cassert>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

int main() {
    namespace fs = std::filesystem;
    const fs::path dir = fs::temp_directory_path() /
        ("strata-ple-origin-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directories(dir);
    const fs::path first = dir / "model-00001-of-00002.gguf";
    const fs::path owner = dir / "model-00002-of-00002.gguf";
    const fs::path sidecar = dir / "external-Q8_0-ple.gguf";
    { std::ofstream f(first, std::ios::binary); f << "MODEL1"; }
    { std::ofstream f(owner, std::ios::binary); f << "MODEL2"; }
    { std::ofstream f(sidecar, std::ios::binary); f << "MODEL2"; }
    const std::vector<std::string> shards = {first.string(), owner.string()};
    assert(strata::native_ple_is_original_shard(shards, 1, ""));
    assert(strata::native_ple_is_original_shard(shards, 1, owner.string()));
    assert(!strata::native_ple_is_original_shard(shards, 1, first.string()));
    assert(!strata::native_ple_is_original_shard(shards, 1, sidecar.string()));
    assert(!strata::native_ple_is_original_shard(shards, 2, owner.string()));
    assert(!strata::native_ple_is_original_shard(shards, 1, (dir / "missing.gguf").string()));
    // Equivalent spellings of the SAME original shard are allowed.
    const fs::path alternate = dir / "subdir" / ".." / owner.filename();
    fs::create_directory(dir / "subdir");
    assert(strata::native_ple_is_original_shard(shards, 1, alternate.string()));
    fs::remove_all(dir);
    return 0;
}
