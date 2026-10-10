"""Iteration 025: source-only regression tests for GGUF mmap ownership and CPU probing.

No model weights, GPU, or external dependencies are needed.
"""
from __future__ import annotations

import builtins
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'tools'))

import setup
from canonical_xcheck import open_shard


class CPUProbeTests(unittest.TestCase):
    def _probe(self, info: str, fn):
        opened = []
        original = builtins.open

        def fake_open(path, *args, **kwargs):
            if str(path) == '/proc/cpuinfo':
                handle = io.StringIO(info)
                opened.append(handle)
                return handle
            return original(path, *args, **kwargs)

        with mock.patch.object(setup, 'WIN', False), \
                mock.patch.object(setup.platform, 'processor', return_value='Test processor'), \
                mock.patch('builtins.open', side_effect=fake_open), \
                mock.patch.dict(setup.os.environ, {'STRATA_ISA_FLOOR': ''}):
            result = fn()
        self.assertEqual(len(opened), 1)
        self.assertTrue(opened[0].closed, 'CPU info file handle must be closed')
        return result

    def test_cpu_info_detects_full_avx512(self):
        info = 'model name : Ryzen Test\nflags : avx2 avx512f avx512bw avx512vl avx512_vnni avx512vbmi\n'
        self.assertEqual(self._probe(info, setup.cpu_info), ('Ryzen Test', True, True))

    def test_cpu_info_without_flags_is_safe(self):
        self.assertEqual(self._probe('model name : Generic CPU\n', setup.cpu_info),
                         ('Generic CPU', False, False))

    def test_cpu_info_missing_model_name_preserves_fallback(self):
        self.assertEqual(self._probe('flags : avx2\n', setup.cpu_info),
                         ('Test processor', True, False))

    def test_cpu_floor_handles_avx_only(self):
        self.assertEqual(self._probe('flags : avx sse4_2 popcnt\n', lambda: setup.cpu_floor(False)), 'avx')

    def test_cpu_floor_handles_missing_flags(self):
        self.assertEqual(self._probe('processor : 0\n', lambda: setup.cpu_floor(False)), 'unsupported')


class GGUFOpenShardTests(unittest.TestCase):
    def test_mapped_file_has_no_unclosed_file_descriptor(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'one.gguf'
            path.write_bytes(b'GGUF' + b'\x00' * 60)
            tracked = []
            original = builtins.open

            def tracking_open(name, *args, **kwargs):
                result = original(name, *args, **kwargs)
                if Path(name) == path:
                    tracked.append(result)
                return result

            with mock.patch('builtins.open', side_effect=tracking_open):
                mm, size = open_shard(path)
            try:
                self.assertEqual(size, 64)
                self.assertEqual(mm[:4], b'GGUF')
                self.assertEqual(len(tracked), 1)
                self.assertTrue(tracked[0].closed, 'mmap creation must release the file handle')
            finally:
                mm.close()

    def test_failed_empty_mapping_still_closes_descriptor(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'empty.gguf'
            path.write_bytes(b'')
            tracked = []
            original = builtins.open

            def tracking_open(name, *args, **kwargs):
                handle = original(name, *args, **kwargs)
                if Path(name) == path:
                    tracked.append(handle)
                return handle

            with mock.patch('builtins.open', side_effect=tracking_open):
                with self.assertRaises((ValueError, OSError)):
                    open_shard(path)
            self.assertEqual(len(tracked), 1)
            self.assertTrue(tracked[0].closed)


if __name__ == '__main__':
    unittest.main()
