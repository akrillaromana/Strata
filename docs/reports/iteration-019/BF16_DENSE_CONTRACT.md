# MTP BF16/Q8 dense contract — итерация 019

1. `tools/mtp_original_rt.py --experts native`: исходный tensor type 30 -> `dense.txt` kind `bf16`, bytes = rows*cols*2; tensor type 8 -> `q8_0`, bytes = rows*cols/32*34. Для `q8_0` cols — логическое число элементов, не физические GGUF bytes.
2. `--experts q2_0`: исторический режим: dense BF16 -> Q8_0, только routed experts могут менять качество с явным `--allow-lossy-expert-conversion`. Это необходимо для старого GPU пути.
3. C++ `mtp_dense_index`: допустимые типы 9 обязательных проекций — `bf16|q8_0`; длина, 256-байтовое выравнивание, пересечения и переполнения проверяются прежде любых CUDA-выделений. `mtp_projection_geometry` сверяет rows/cols с параметрами `ModelGeometry`.
4. Dense FC и attention BF16: `bf16_gemv_fp32_mmvf_multi` с F32 activation; Q8: `native_mmvq` с Q8_1 activation. Shared gate/up/down BF16: отдельный CUDA BF16 GEMV, down после SwiGLU использует FP32 без промежуточного Q8_1.
5. `Prefill::draft_kv` остаётся ускорением только для полного комплекта Q8_0 dense-проекций. С BF16 вызывающая сторона использует `MtpDrafter::prefill` с новым BF16 dispatch.
6. Отсутствие CUDA-компиляции и исходных GGUF означает, что это реализованный и автономно проверенный код, но не подтверждённый аппаратный запуск.
