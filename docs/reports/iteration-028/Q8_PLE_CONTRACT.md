# Q8_0 PLE / n-gram and batch prefill — iteration 028

## Original GGUF provenance

The owner's Q8_0 n-gram remains the original `per_layer_token_embd.weight` inside the *complete original* model GGUF split, `shape=[160,320001536]`, physical 170 bytes/row (5 Q8_0 blocks), without IQ4_NL substitution or sidecars. The Python preflight checks the tensor's type, shape and physical bounds *before* calling the complete shared directory audit; it never reads its ~54.4 GB payload.

A previously valid-looking Q8_0 table can exist beside a truncated Q6_K/Q8_0 tensor, overlapping offsets, duplicate tensor names or inconsistent split metadata. Such a file must not be reported as an acceptable native model. The shared `model_compat.inspect()` now rejects these situations before preflight reports success. This audit cannot establish whether the original weights are numerically valid.

## Batch postops launch

`native_ple_batch_shape(T)` checks positive T, grid rows `T*4`, grid blocks `(T*10240+255)/256` against signed 32-bit grid limits and computes lengths of the token-key, value and gate allocations without overflow. Both CUDA/HIP and experimental SYCL reject overlapping input/scratch/output buffer ranges and outputs overlapping immutable weights before dispatch. PLE convolution weights are FP16 and need 2-byte alignment; float buffers need 4-byte alignment. Gamma aliases with each other are not assumed to be invalid, but none may overlap writable batch buffers.

## Still not demonstrated

No compilation of native_ple_postops CUDA/HIP/SYCL, numeric GPU parity, actual Q8_0 Unsloth/Huihui weights, 5-shard Q6_K compute, IQ3_S RCO topology, real MTP/shared GGUF, or end-to-end inference has been performed. "Header safe" is not synonymous with "runs this model correctly".
