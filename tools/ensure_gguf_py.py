"""Подготовка строго закреплённой GGUF-библиотеки для упаковки Q8_0.

Пользуется существующей копией от сборки CMake; если её нет, при явном
--install-if-missing загружает только подпапку gguf-py из закреплённой ревизии.
Остальные исходники llama.cpp не устанавливает. Исходные GGUF не затрагивает.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import sys
import tempfile
import urllib.request
import zipfile

from _paths import ENGINE, gguf_py

LLAMA_COMMIT = "3cf03257f219afbe7334045ff7c6a06ac68c627d"
SOURCE_URL = f"https://github.com/ggml-org/llama.cpp/archive/{LLAMA_COMMIT}.zip"
VENDOR_ROOT = ENGINE / "third_party" / "strata-gguf-py"
MAX_ARCHIVE_BYTES = 150 * 1024 * 1024
MAX_EXTRACT_BYTES = 35 * 1024 * 1024


def validate_import() -> str:
    path = gguf_py()
    if path not in sys.path:
        sys.path.insert(0, path)
    from gguf import GGMLQuantizationType, quants  # noqa: PLC0415
    for kind in ("Q8_0", "BF16"):
        if not hasattr(GGMLQuantizationType, kind):
            raise RuntimeError(f"В {path} не поддерживается тип {kind}")
    if not callable(quants.dequantize) or not callable(quants.quantize):
        raise RuntimeError(f"В {path} отсутствуют методы квантования GGUF")
    return path


def extract_pinned_gguf(archive: Path, target: Path) -> None:
    """Отбор только gguf-py из архива llama.cpp; запрет выхода за target."""
    prefix = f"llama.cpp-{LLAMA_COMMIT}/gguf-py/"
    license_name = f"llama.cpp-{LLAMA_COMMIT}/LICENSE"
    with zipfile.ZipFile(archive) as z:
        selected = [m for m in z.infolist() if m.filename.startswith(prefix)]
        if not selected or not any(m.filename == prefix + "gguf/__init__.py" for m in selected):
            raise ValueError("Полученный архив не содержит ожидаемой gguf-py закреплённой ревизии")
        if sum(m.file_size for m in selected) > MAX_EXTRACT_BYTES:
            raise ValueError("Размер gguf-py в архиве превышает допустимый предел")
        if target.exists():
            raise FileExistsError(f"Целевой каталог уже существует: {target}")
        target.mkdir(parents=True, exist_ok=False)
        for item in selected:
            relative = item.filename[len(prefix):]
            if not relative:
                continue
            components = Path(relative).parts
            if (relative.startswith("/") or "\\" in relative or ":" in relative or
                any(s in (".", "..") for s in components)):
                raise ValueError(f"Недопустимый путь в архиве: {item.filename}")
            # Запрет архивных символических ссылок: файловая система не должна
            # получить ссылку за пределы целевого каталога.
            unix_mode = (item.external_attr >> 16) & 0o170000
            if unix_mode == 0o120000:
                raise ValueError(f"Символическая ссылка в архиве: {item.filename}")
            dest = target.joinpath(*components)
            if item.is_dir():
                dest.mkdir(parents=True, exist_ok=True)
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(item) as source, dest.open("xb") as out:
                shutil.copyfileobj(source, out)
        # Сохраняем условия лицензии внешнего кода при локальной установке.
        if license_name in z.namelist():
            with z.open(license_name) as source, (target / "UPSTREAM-LICENSE.txt").open("xb") as out:
                shutil.copyfileobj(source, out)
    if not (target / "gguf" / "__init__.py").is_file():
        raise RuntimeError("Библиотека GGUF после извлечения неполная")


def fetch_pinned_gguf() -> Path:
    root = VENDOR_ROOT.parent
    root.mkdir(parents=True, exist_ok=True)
    if VENDOR_ROOT.exists():
        raise FileExistsError(
            f"Неполная локальная библиотека: {VENDOR_ROOT}. "
            "Не удаляю её автоматически; проверьте содержимое."
        )
    with tempfile.TemporaryDirectory(prefix="strata-gguf-") as tmp:
        archive = Path(tmp) / "llama.zip"
        req = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "Strata-Q8-pack/045"})
        with urllib.request.urlopen(req, timeout=60) as response, archive.open("wb") as out:
            written = 0
            while True:
                part = response.read(1024 * 1024)
                if not part:
                    break
                written += len(part)
                if written > MAX_ARCHIVE_BYTES:
                    raise ValueError("Исходный архив llama.cpp превышает лимит 150 МиБ")
                out.write(part)
        if not zipfile.is_zipfile(archive):
            raise ValueError("Сервер вернул не ZIP-архив llama.cpp")
        stage = root / ("strata-gguf-py.partial-" + os.urandom(4).hex())
        try:
            extract_pinned_gguf(archive, stage)
            stage.rename(VENDOR_ROOT)
        except Exception:
            # Не удаляем повреждённую пользовательскую копию. Временный
            # каталог с уникальным именем остаётся для диагностики.
            if stage.exists():
                print(f"Незавершённое извлечение сохранено: {stage}", file=sys.stderr)
            raise
    return VENDOR_ROOT


def main() -> int:
    parser = argparse.ArgumentParser(description="Проверка закреплённой gguf-py для Q8_0")
    parser.add_argument("--install-if-missing", action="store_true")
    args = parser.parse_args()
    try:
        path = validate_import()
        print(f"[OK] gguf-py: {path}", flush=True)
        return 0
    except (SystemExit, ImportError, RuntimeError) as exc:
        if not args.install_if_missing:
            print(f"GGUF недоступна: {exc}", file=sys.stderr)
            return 2
        print("gguf-py не найдена в каталоге CMake или third_party.", flush=True)
        print(f"Получение закреплённой ревизии llama.cpp {LLAMA_COMMIT[:12]} ...", flush=True)
    try:
        installed = fetch_pinned_gguf()
        print(f"Исходники gguf-py сохранены: {installed}", flush=True)
        path = validate_import()
        print(f"[OK] GGUF доступна для упаковки Q8_0: {path}", flush=True)
        return 0
    except Exception as exc:
        print(f"Не удалось подготовить gguf-py: {exc}", file=sys.stderr)
        print("Проверьте интернет или каталог CMake. Исходные GGUF и RAM-диск не изменены.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
