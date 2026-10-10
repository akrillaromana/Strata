"""Regression tests for non-destructive legacy pack creation.

No GGUF weights are needed. Never permit a partial rebuild to retain an old
manifest (especially when an existing Q4/Q8 pack is the destination).
"""
from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import strata_pack


class PackDestinationSafety(unittest.TestCase):
    def test_any_pack_marker_blocks_build_without_touching_old_bytes(self):
        for marker in strata_pack.PACK_MARKERS:
            with self.subTest(marker=marker), tempfile.TemporaryDirectory() as directory:
                path = Path(directory)
                existing = path / marker
                existing.write_bytes(b"do not overwrite")
                with patch.object(strata_pack.G, "GGUFFile", side_effect=AssertionError("must not open GGUF")):
                    with contextlib.redirect_stdout(io.StringIO()):
                        result = strata_pack.build(path / "missing.gguf", path, None, True)
                self.assertEqual(result, 1)
                self.assertEqual(existing.read_bytes(), b"do not overwrite")

    def test_force_invalidates_all_pack_markers_before_any_gguf_read(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for name in strata_pack.PACK_MARKERS:
                (path / name).write_bytes(b"stale")
            def assert_stale_markers_removed(_):
                for name in strata_pack.PACK_MARKERS:
                    self.assertFalse((path / name).exists())
                raise ValueError("synthetic GGUF error")
            with patch.object(strata_pack.G, "GGUFFile", side_effect=assert_stale_markers_removed):
                with self.assertRaisesRegex(ValueError, "synthetic GGUF error"):
                    strata_pack.build(path / "missing.gguf", path, None, True, force=True)

    def test_non_pack_directory_is_not_considered_occupied(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "notes.txt").write_text("keep")
            self.assertIsNone(strata_pack.occupied(path))

    def test_command_line_has_opt_in_force(self):
        with patch.object(strata_pack, "build", return_value=0) as do_build:
            with patch.object(sys, "argv", ["strata_pack.py", "build", "--gguf", "x.gguf", "--out", "pack"]):
                self.assertEqual(strata_pack.main(), 0)
                self.assertFalse(do_build.call_args.args[-1])
            with patch.object(sys, "argv", ["strata_pack.py", "build", "--gguf", "x.gguf", "--out", "pack", "--force"]):
                self.assertEqual(strata_pack.main(), 0)
                self.assertTrue(do_build.call_args.args[-1])


if __name__ == "__main__":
    unittest.main()
