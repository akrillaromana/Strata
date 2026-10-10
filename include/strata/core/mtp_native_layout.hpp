// Portable, CPU-only manifest contract for ORIGINAL Q8_0/BF16 MTP expert weights.
// A native experts.txt file is authoritative: malformed native data MUST NOT fall back to Q2_0.
#pragma once
#include <charconv>
#include <cstdint>
#include <istream>
#include <limits>
#include <sstream>
#include <string>

namespace strata::core {

struct MtpNativeLayout {
    // 8 = ggml Q8_0, 30 = ggml BF16; two independent quantizations.
    int gate_kind = 0, down_kind = 0;
    uint64_t experts = 0, hidden = 0, ff = 0;
    uint64_t gate_bytes = 0, down_bytes = 0, expert_bytes = 0;
};

inline bool mtp_native_uint(const std::string& value, uint64_t& output) {
    if (value.empty()) return false;
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), output);
    return parsed.ec == std::errc{} && parsed.ptr == value.data() + value.size();
}

inline bool mtp_native_layout(std::istream& input, uint64_t file_size, uint64_t expected_experts,
                              uint64_t expected_hidden, uint64_t expected_ff, MtpNativeLayout& result,
                              std::string& err) {
    MtpNativeLayout out{};
    std::string line, magic, gate, down, n, h, ff, extra;
    if (!std::getline(input, line) || line.size() > 256 || input.bad()) {
        err = "mtp: missing/overlong native experts.txt"; return false;
    }
    std::istringstream s(line);
    if (!(s >> magic >> gate >> down >> n >> h >> ff) || (s >> extra) ||
        magic != "mtp_native_experts_v1" ||
        (gate != "q8_0" && gate != "bf16") || (down != "q8_0" && down != "bf16") ||
        !mtp_native_uint(n, out.experts) || !mtp_native_uint(h, out.hidden) ||
        !mtp_native_uint(ff, out.ff) || out.experts != expected_experts ||
        out.hidden != expected_hidden || out.ff != expected_ff ||
        !out.experts || !out.hidden || !out.ff || out.hidden % 32 || out.ff % 32) {
        err = "mtp: incompatible native expert manifest/geometry"; return false;
    }
    // No additional lines, even a silent second manifest, are permitted.
    if (std::getline(input, line) || input.bad()) {
        err = "mtp: trailing records in native experts.txt"; return false;
    }
    out.gate_kind = gate == "q8_0" ? 8 : 30;
    out.down_kind = down == "q8_0" ? 8 : 30;
    auto matrix_bytes = [](uint64_t rows, uint64_t cols, int kind, uint64_t& bytes) {
        const uint64_t per = kind == 8 ? 34 : 64; // bytes per 32 logical elements
        if (rows == 0 || cols == 0 || rows > UINT64_MAX / cols) return false;
        const uint64_t values = rows * cols;
        if (values / 32 > UINT64_MAX / per) return false;
        bytes = values / 32 * per;
        return true;
    };
    if (out.ff > UINT64_MAX / 2 ||
        !matrix_bytes(out.ff * 2, out.hidden, out.gate_kind, out.gate_bytes) ||
        !matrix_bytes(out.hidden, out.ff, out.down_kind, out.down_bytes) ||
        out.gate_bytes > UINT64_MAX - out.down_bytes) {
        err = "mtp: native expert byte count overflow"; return false;
    }
    out.expert_bytes = out.gate_bytes + out.down_bytes;
    if (out.experts > UINT64_MAX / out.expert_bytes ||
        out.experts * out.expert_bytes != file_size) {
        err = "mtp: native experts.bin size mismatch"; return false;
    }
    result = out;
    return true;
}
} // namespace strata::core
