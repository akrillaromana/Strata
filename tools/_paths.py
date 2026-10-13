"""Обнаружение Python-модуля GGUF из закреплённой ревизии llama.cpp.

Сначала используются явно заданный путь и уже загруженный при сборке CMake
исходный код. Системные пакеты другой версии не подставляются автоматически:
несовпадение алгоритма округления способно изменить подготовленные веса.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1]


def gguf_candidates(root: Path | None = None):
    root = root or ENGINE
    explicit = os.environ.get("STRATA_GGUF_PY")
    if explicit:
        yield Path(explicit)
    yield root / "third_party" / "llama.cpp" / "gguf-py"
    yield root / "third_party" / "strata-gguf-py"
    # CMake FetchContent скачивает ТУ ЖЕ закреплённую ревизию llama.cpp,
    # что указана в setup.py. В Windows-сборке Strata она находится здесь.
    yield root / "build-iq3s-ninja-release" / "_deps" / "strata_llamacpp-src" / "gguf-py"
    yield root / "build" / "_deps" / "strata_llamacpp-src" / "gguf-py"
    for build in sorted(root.glob("build*")):
        if build.is_dir():
            yield build / "_deps" / "strata_llamacpp-src" / "gguf-py"
    if len(root.parents) >= 2:
        yield root.parents[1] / ".ref" / "llama.cpp" / "gguf-py"


def gguf_py() -> str:
    seen = set()
    for candidate in gguf_candidates():
        p = Path(candidate)
        norm = os.path.normcase(str(p.absolute()))
        if norm in seen:
            continue
        seen.add(norm)
        if (p / "gguf" / "__init__.py").is_file():
            return str(p)
    sys.exit(
        "Не найден gguf-py закреплённой версии llama.cpp. "
        "Запустите tools/ensure_gguf_py.py --install-if-missing; "
        "либо задайте STRATA_GGUF_PY. Проверен и каталог CMake build-iq3s-ninja-release/_deps."
    )


def add_gguf_py() -> None:
    p = gguf_py()
    if p not in sys.path:
        sys.path.insert(0, p)
