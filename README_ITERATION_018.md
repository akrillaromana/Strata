# Strata Personal Custom v0.1.39 — iteration 018

Персональный форк для конфигурации владельца. **Не рекомендован другим пользователям для запуска «как есть».**

Новая кодовая возможность: исходные routed MTP experts BF16/Q8_0 сохраняются побайтово в собственном `experts.bin`, с проверяемым `experts.txt` (без конвертации в Q2_0), GPU path в `src/kernels/cuda/mtp_native_experts.cu` выбирается во время `MtpDrafter::load`. Прежний Q2_0 путь остаётся.

Дополнительная опция локального Python-инструмента `tools/mtp_original_rt.py`: `--experts native` (без флага lossy), тогда как прежнее преобразование `--experts q2_0` требует `--allow-lossy-expert-conversion`. Оба выдают **подготовленный runtime-каталог**, а не готовый запуск исходного GGUF.

Полная техническая матрица в `docs/reports/iteration-018/{REPORT,TASKS}.md`. Персональные профили `PERSONAL_START_E_ai_Strata-Q4/`, `tools/windows/q4-local-profiles/`, пути E:/R: и все восемь вариантов моделей сохранены.

**Статус:** 129 Python, 55 JavaScript, CPU C++ манифест и CPU числовой oracle прошли. CUDA-сборка и реальная модель не запускались; нативные MTP эксперты реализованы в исходниках, но нельзя утверждать полную GPU-проверенность или готовность всего проекта.
