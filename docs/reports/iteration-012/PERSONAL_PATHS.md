# Персональные пути моделей и конфигураций

Это не переносимый дистрибутив. Профили **жёстко** ориентированы на личную машину пользователя:

| Роль | Путь |
|---|---|
| Установка/сервер/бинарник | `E:\ai\Strata-Q4`, `E:\ai\Strata-Q4\serve\server.py`, `E:\ai\Strata-Q4\engine\strata.exe` |
| Пакеты, MTP, IQ3_S | `E:\ai\Strata-data`, `E:\ai\Strata-data\mtp\rt`, `E:\ai\Strata-data\models\IQ3_S` |
| Unsloth split GGUF | `E:\ai\models\unsloth\Qwen3.8-Flash-Next-GGUF` |
| Huihui split GGUF | `E:\ai\models\huihui-ai\Huihui-Qwen3.8-Flash-Next-abliterated-GGUF` |
| Нативный движок | `E:\ai\Strata-Q4\engine\strata.exe` |
| RAM-модели | `R:\q4-model`, `R:\iq3s-model`, legacy Q8 `R:\q8-model` |
| RAM-рантаймы | `R:\strata-q4-runtime`, `R:\strata-iq3s-runtime`, legacy Q8 `R:\strata-runtime-q8` |
| Драйвер RAM-диска | `C:\Program Files\AIM Toolkit\aim_ll.exe` |

Сценарии **разработаны с условием плоского расположения непосредственно в `E:\ai\Strata-Q4`**, рядом с `PREPARE-HUIHUI-Q4.py` и конфигурациями. Их расположение внутри репозитория `tools/windows/q4-local-profiles` — только место хранения исходников. Для удобства копирования в архиве имеется плоский каталог `PERSONAL_START_E_ai_Strata-Q4`, являющийся проверенной идентичной копией. Сейчас копировать их на E: не нужно — пользователь работает только с форком на GitHub.

Статические JSON могут описывать старое размещение файлов на R: и не заменяют программу подготовки RAM-диска. Единственный Q8 профиль, доставленный в `Strata-Q4(2).zip`, требует PLE `IQ4_NL`, и не решает задачу полностью нативного Q8_0. Нельзя также подменять Huihui pack пакетом Unsloth.

Примечание о безопасности: API выставлен на `0.0.0.0:8080` по исторической пользовательской конфигурации; запускать только в доверенной среде, при необходимости отдельно настроить ключ/сетевые ограничения.
