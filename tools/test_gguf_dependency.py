"""Проверки обнаружения и безопасного извлечения gguf-py без сети и GGUF."""
from __future__ import annotations

from pathlib import Path
import io
import os
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _paths
import ensure_gguf_py


class GgufDependencyTest(unittest.TestCase):
    def test_cmake_source_is_discovered_without_setup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cached = root / "build-iq3s-ninja-release" / "_deps" / "strata_llamacpp-src" / "gguf-py"
            (cached / "gguf").mkdir(parents=True)
            (cached / "gguf" / "__init__.py").write_text("# GGUF", encoding="utf-8")
            with patch.object(_paths, "ENGINE", root), patch.dict(os.environ, {}, clear=True):
                self.assertEqual(_paths.gguf_py(), str(cached))

    def test_explicit_path_has_priority(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            preferred = root / "own-gguf"
            (preferred / "gguf").mkdir(parents=True)
            (preferred / "gguf" / "__init__.py").write_text("# GGUF", encoding="utf-8")
            with patch.object(_paths, "ENGINE", root), patch.dict(os.environ, {"STRATA_GGUF_PY": str(preferred)}):
                self.assertEqual(_paths.gguf_py(), str(preferred))

    def test_incomplete_cache_does_not_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "build-iq3s-ninja-release" / "_deps" / "strata_llamacpp-src" / "gguf-py" / "gguf").mkdir(parents=True)
            with patch.object(_paths, "ENGINE", root), patch.dict(os.environ, {}, clear=True):
                with self.assertRaises(SystemExit):
                    _paths.gguf_py()

    def test_extract_pinned_only_gguf(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / "source.zip"
            prefix = f"llama.cpp-{ensure_gguf_py.LLAMA_COMMIT}/"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr(prefix + "gguf-py/gguf/__init__.py", "# library")
                z.writestr(prefix + "gguf-py/gguf/quants.py", "# algorithms")
                z.writestr(prefix + "ggml/src/unrelated.cpp", "leave out")
                z.writestr(prefix + "LICENSE", "MIT License")
            out = root / "vendored"
            ensure_gguf_py.extract_pinned_gguf(archive, out)
            self.assertTrue((out / "gguf" / "quants.py").is_file())
            self.assertFalse((out / "ggml").exists())
            self.assertEqual((out / "UPSTREAM-LICENSE.txt").read_text(), "MIT License")

    def test_archive_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / "evil.zip"
            prefix = f"llama.cpp-{ensure_gguf_py.LLAMA_COMMIT}/gguf-py/"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr(prefix + "gguf/__init__.py", "# base")
                z.writestr(prefix + "../../../attack.txt", "NO")
            with self.assertRaisesRegex(ValueError, "Недопустимый путь"):
                ensure_gguf_py.extract_pinned_gguf(archive, root / "safe")
            self.assertFalse((root / "attack.txt").exists())

    def test_no_download_without_consent(self):
        with patch.object(ensure_gguf_py, "validate_import", side_effect=SystemExit("missing")), \
                patch.object(ensure_gguf_py, "fetch_pinned_gguf") as fetch, \
                patch("sys.argv", ["ensure_gguf_py.py"]):
            self.assertEqual(ensure_gguf_py.main(), 2)
            fetch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
