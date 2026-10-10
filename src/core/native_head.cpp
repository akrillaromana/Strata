#include "strata/core/native_head.hpp"
#include "strata/core/native_embed_allocation.hpp"
#include "strata/artifact/gguf_reader.hpp"
#include "strata/kernels/iq_kernels.hpp"
#include "strata/kernels/native_mmvq.hpp"

#include <cuda_runtime.h>
#include <climits>
#include <cstdio>
#include <cstring>
#include <exception>
#include <stdexcept>

namespace strata::core {

NativeHead::~NativeHead() {
    if (scratch_) cudaFree(scratch_);
    if (weights_) cudaFree(weights_);
}

bool NativeHead::load(const std::vector<std::string>& shards, int64_t n_in, int64_t n_out, std::string& err) {
    if (loaded()) { err = "native head is already loaded"; return false; }
    if (n_in <= 0 || n_out <= 0 || n_in > INT_MAX || n_out > INT_MAX || n_in % 256) {
        err = "native head requires positive int32 dimensions and whole 256-value rows";
        return false;
    }
    try {
        // The architecture is the metadata shard's; output.weight comes from whichever shard holds it (shard 2
        // of Unsloth's UD-Q4_K_XL, whose shard 1 holds no tensor).  GgufModel refuses a duplicate across shards.
        const strata::GgufModel model(shards);
        err = strata::check_architecture(model.meta());
        if (!err.empty()) return false;
        // Validate the ENTIRE multishard GGUF, including unrelated tensors and
        // shards, before allocating or copying the selected output projection.
        strata::validate_native_model_payloads(model);
        size_t at = 0;
        const strata::TensorInfo* tensor = model.find("output.weight", &at);
        if (!tensor) {
            err = "native head: output.weight is absent";
            return false;
        }
        const strata::GgufFile& gguf = model.shard(at);
        if (!strata::kernels::native_mmvq_supported((int) tensor->type) || tensor->shape.size() != 2 ||
            tensor->shape[0] != (uint64_t) n_in || tensor->shape[1] != (uint64_t) n_out) {
            err = "native head: expected a natively supported output.weight with the canonical head dimensions";
            return false;
        }
        const uint64_t bytes = strata::kernels::native_mmvq_weight_bytes((int) tensor->type, (int) n_in, (int) n_out);
        const uint64_t payload = gguf.file_size() - gguf.data_start();
        if (tensor->offset > payload || bytes > payload - tensor->offset) {
            err = "native head: truncated output.weight payload";
            return false;
        }
        void* weights = nullptr;
        void* scratch = nullptr;
        cudaError_t status = cudaMalloc(&weights, bytes);
        if (status == cudaSuccess)
            status = cudaMalloc(&scratch, strata::kernels::native_q8_1_bytes((int) n_in, 1));
        if (status == cudaSuccess)
            status = cudaMemcpy(weights, gguf.tensor_data(*tensor), bytes, cudaMemcpyHostToDevice);
        if (status != cudaSuccess) {
            if (scratch) cudaFree(scratch);
            if (weights) cudaFree(weights);
            err = std::string("native head upload: ") + cudaGetErrorString(status);
            return false;
        }
        weights_ = weights;
        scratch_ = scratch;
        bytes_ = bytes;
        n_in_ = (int) n_in;
        n_out_ = (int) n_out;
        type_ = (int) tensor->type;
        return true;
    } catch (const std::exception& error) {
        err = std::string("native head: ") + error.what();
        return false;
    }
}

bool NativeHead::run(const float* mixed, float* logits, void* stream, std::string& err) const {
    if (!loaded() || !mixed || !logits || !stream) {
        err = "native head requires loaded weights, device buffers and an explicit stream";
        return false;
    }
    try {
        if (type_ == 13) {
            strata::kernels::native_q5_k_f32(weights_, mixed, scratch_, logits, n_in_, n_out_, 1, stream);
        } else {
            strata::kernels::native_quantize_q8_1(mixed, scratch_, n_in_, 1, stream);
            strata::kernels::native_mmvq(type_, weights_, scratch_, logits, n_in_, n_out_, 1, stream);
        }
    } catch (const std::exception& error) {
        err = std::string("native head launch: ") + error.what();
        return false;
    }
    const cudaError_t status = cudaPeekAtLastError();
    if (status != cudaSuccess) {
        err = std::string("native head launch: ") + cudaGetErrorString(status);
        return false;
    }
    return true;
}

// ================================ plan v0.3 P6: THE NATIVE EMBEDDING ================================

namespace {
const NativeEmbed* g_embed = nullptr;
}
void set_native_embed(const NativeEmbed* e) { g_embed = e; }
const NativeEmbed* native_embed() { return g_embed; }

NativeEmbed::~NativeEmbed() {
    if (host_) cudaFreeHost(host_);
    else if (dev_) cudaFree(const_cast<void*>(dev_));   // the VRAM fallback below
}

bool NativeEmbed::load(const std::vector<std::string>& shards, int64_t n_embd, int64_t n_vocab, std::string& err) {
    // A failed load leaves the object reusable; an already published table must
    // never be replaced or freed by a second load attempt.
    if (host_ || dev_) {
        err = "native embedding is already loaded";
        return false;
    }
    try {
        const strata::GgufModel model(shards);
        const strata::MetaValue* arch = model.meta().get("general.architecture");
        err = arch != nullptr && arch->s == "strata-embd" ? std::string() : strata::check_architecture(model.meta());
        if (!err.empty()) { err = "native embedding: " + err; return false; }
        strata::validate_native_model_payloads(model);
        size_t at = 0;
        const strata::TensorInfo* t = model.find("token_embd.weight", &at);
        if (!t) {
            err = "native embedding: token_embd.weight is absent";
            return false;
        }
        const strata::GgufFile& gguf = model.shard(at);
        if (n_embd <= 0 || n_vocab <= 0 || n_vocab > INT32_MAX || n_embd % 256 != 0 ||
            !strata::kernels::embed_type_supported((int) t->type)) {
            err = "native embedding: invalid dimensions or unsupported GPU dequantizer";
            return false;
        }
        const size_t row_bytes = strata::kernels::iq_row_bytes((int) t->type, n_embd);
        const uint64_t bytes = strata::native_embedding_checked_bytes(*t, n_embd, n_vocab, row_bytes);
        if (!model.in_bounds(*t, at) || strata::tensor_payload_bytes(*t) != bytes) {
            err = "native embedding: token_embd.weight's payload is truncated or not " + std::to_string(bytes) +
                  " B (" + gguf.path() + ")";
            return false;
        }

        // All host/GPU allocations belong to this transaction until success.
        // CUDA/HIP fallback must work not only if pinning fails, but also if
        // the driver cannot map an otherwise successfully pinned allocation.
        NativeEmbedAllocation staging(
            [](void* p) { (void) cudaFreeHost(p); },
            [](void* p) { (void) cudaFree(p); });
        void* pinned = nullptr;
        const cudaError_t pinned_status = cudaHostAlloc(&pinned, bytes, cudaHostAllocMapped | cudaHostAllocPortable);
        if (pinned) staging.set_host(pinned);
        if (pinned_status == cudaSuccess && pinned != nullptr) {
            std::memcpy(pinned, gguf.tensor_data(*t), bytes);
            void* alias = nullptr;
            if (cudaHostGetDevicePointer(&alias, pinned, 0) == cudaSuccess && alias != nullptr) {
                staging.set_device_alias(alias);
            } else {
                // A mapped alias is unavailable on some Windows HIP and WSL
                // configurations; falling back to VRAM also works with CUDA.
                (void) cudaGetLastError();
                void* gpu = nullptr;
                const cudaError_t allocate = cudaMalloc(&gpu, bytes);
                if (gpu) staging.set_device_owned(gpu);
                if (allocate != cudaSuccess || !gpu ||
                    cudaMemcpy(gpu, pinned, bytes, cudaMemcpyHostToDevice) != cudaSuccess) {
                    err = "native embedding: no mapped device alias and VRAM fallback failed";
                    return false;
                }
                staging.drop_host_after_copy();
                std::fprintf(stderr, "strata: native embedding: pinned alias unavailable, kept in VRAM instead\n");
            }
        } else {
            // Host allocation can fail on WSL; avoid retaining any partial
            // pinned allocation before committing the VRAM fallback.
            (void) cudaGetLastError();
            void* gpu = nullptr;
            const cudaError_t allocate = cudaMalloc(&gpu, bytes);
            if (gpu) staging.set_device_owned(gpu);
            if (allocate != cudaSuccess || !gpu ||
                cudaMemcpy(gpu, gguf.tensor_data(*t), bytes, cudaMemcpyHostToDevice) != cudaSuccess) {
                err = "native embedding: cannot pin " + std::to_string(bytes >> 20) + " MiB, nor place it in VRAM";
                return false;
            }
            staging.drop_host_after_copy();
            std::fprintf(stderr, "strata: native embedding: cannot pin %llu MiB, kept in VRAM instead\n",
                         (unsigned long long) (bytes >> 20));
        }
        staging.commit(host_, dev_);
        bytes_ = bytes;
        row_ = row_bytes;
        type_ = (int) t->type;
        n_embd_ = n_embd;
        n_vocab_ = n_vocab;
        return true;
    } catch (const std::exception& e) {
        err = std::string("native embedding: ") + e.what();
        return false;
    }
}

void NativeEmbed::gather_dev(const int32_t* tokens, int64_t n_tok, float* out, void* stream) const {
    if (!dev_) throw std::logic_error("native embedding: gather from unloaded table");
    strata::kernels::iq_embed_rows(type_, dev_, row_, tokens, n_tok, n_embd_, out, stream);
}

void NativeEmbed::gather_one(int64_t token, float* out, void* stream) const {
    if (!dev_) throw std::logic_error("native embedding: gather from unloaded table");
    if (token < 0 || token >= n_vocab_)
        throw std::out_of_range("native embedding: token id outside vocabulary");
    strata::kernels::iq_dequant_f32(type_, (const uint8_t*) dev_ + (size_t) token * row_, n_embd_, out, stream);
}

}  // namespace strata::core
