"""Offline regression tests for the fork's donor GGUF inspector bounds."""
import io
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import quantscope as q


class Headers(unittest.TestCase):
    def test_reads_only_requested_http_range(self):
        class Response:
            status = 206
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, n):
                self.max_read = n
                return b'xyz'
        reply = Response()
        with patch.object(q.urllib.request, 'urlopen', return_value=reply):
            self.assertEqual(q.http('https://example.test/model.gguf', 40, 42), b'xyz')
            self.assertEqual(reply.max_read, 4)

    def test_rejects_http_server_ignoring_nonzero_range(self):
        class Response:
            status = 200
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, n):
                self.fail('body should not be read')
        with patch.object(q.urllib.request, 'urlopen', return_value=Response()):
            with self.assertRaises(RuntimeError):
                q.http('https://example.test/model.gguf', 40, 43)

    def test_rejects_oversized_response(self):
        class Response:
            status = 206
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, n): return b'x' * n
        with patch.object(q.urllib.request, 'urlopen', return_value=Response()):
            with self.assertRaises(RuntimeError):
                q.http('https://example.test/model.gguf', 40, 43)

    def test_rejects_invalid_local_ranges(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'm.gguf'
            p.write_bytes(b'GGUF')
            src = q.Source('m.gguf', 4, path=str(p))
            for offset, length in [(-1, 1), (5, 0), (0, -1)]:
                with self.subTest(offset=offset, length=length):
                    with self.assertRaises(ValueError): src.read(offset, length)

    def test_bounded_header_strings(self):
        class Reader:
            def u64(self): return (16 << 20) + 1
            def take(self, n): raise AssertionError('oversized string read')
        with self.assertRaises(ValueError): q.Buffered.string(Reader())

    def test_oversized_tensor_count_fails_before_allocating(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'm.gguf'
            p.write_bytes(b'GGUF' + struct.pack('<IQQ', 3, 500001, 0))
            with self.assertRaisesRegex(ValueError, 'implausible'):
                q.read_gguf(q.Source('m.gguf', p.stat().st_size, path=str(p)))

    def test_model_label_escaped(self):
        from serve.prometheus import Latencies, render, wants_prometheus
        text = render({'engine': {'model': 'foo"\nstrata:injected 3', 'max_context': 2}}, Latencies().snapshot())
        self.assertIn('model_name="foo\\"\\nstrata:injected 3"', text)
        self.assertNotIn('\nstrata:injected 3', text)
        self.assertFalse(wants_prometheus('application/json', 'notformat=prometheus'))
        self.assertTrue(wants_prometheus('application/json', 'format=prometheus'))


if __name__ == '__main__':
    unittest.main()
