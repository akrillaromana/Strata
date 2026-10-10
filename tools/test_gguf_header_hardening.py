"""CPU-only GGUF malformed Q6_K/Q8_0 header contract (no model or CUDA)."""
import struct
import tempfile
import unittest
from pathlib import Path

from tools.gguf_reader import GGUFFile


def s(text):
    raw = text.encode('utf-8')
    return struct.pack('<Q', len(raw)) + raw


def kv(key, value, kind=4):
    return s(key) + struct.pack('<I', kind) + (s(value) if kind == 8 else struct.pack('<I', value))


def fixture(tensors, metadata=(), *, header_count=None, raw_override=None):
    if raw_override is not None:
        return raw_override
    out = bytearray(b'GGUF' + struct.pack('<IQQ', 3, len(tensors) if header_count is None else header_count, len(metadata)))
    for row in metadata:
        out += kv(*row)
    offset = 0
    payload = bytearray()
    for name, quant in tensors:
        out += s(name) + struct.pack('<IQIQ', 1, 256 if quant == 14 else 32, quant, offset)
        payload += bytes(210 if quant == 14 else 34)
        offset = len(payload)
    out += bytes(-len(out) % 32)
    return out + payload


class GGUFHeaderHardening(unittest.TestCase):
    def run_file(self, b):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'candidate-Q6_K.gguf'
            p.write_bytes(b)
            return GGUFFile(p)

    def test_valid_q6_and_q8(self):
        result = self.run_file(fixture([('blk.0.attn_q.weight', 14), ('blk.0.attn_k.weight', 8)]))
        self.assertEqual([t.expected_bytes() for t in result.tensors], [210, 34])

    def test_duplicate_metadata(self):
        with self.assertRaisesRegex(ValueError, 'duplicate metadata'):
            self.run_file(fixture([], [('split.count', 2), ('split.count', 1)]))

    def test_bad_alignment(self):
        with self.assertRaisesRegex(ValueError, 'general.alignment'):
            self.run_file(fixture([], [('general.alignment', 3)]))

    def test_wrong_alignment_type(self):
        with self.assertRaisesRegex(ValueError, 'general.alignment'):
            self.run_file(fixture([], [('general.alignment', '32', 8)]))

    def test_implausible_tensor_count(self):
        with self.assertRaisesRegex(ValueError, 'directory count'):
            self.run_file(fixture([], header_count=(1 << 63)))

    def test_oversized_string(self):
        with self.assertRaisesRegex(ValueError, 'bounds|directory count'):
            self.run_file(b'GGUF' + struct.pack('<IQQQ', 3, 0, 1, (1 << 64) - 1))

    def test_duplicate_tensor(self):
        with self.assertRaisesRegex(ValueError, 'duplicate tensor name'):
            self.run_file(fixture([('blk.0.attn_q.weight', 14), ('blk.0.attn_q.weight', 8)]))

    def test_short_header(self):
        with self.assertRaisesRegex(ValueError, 'bounds'):
            self.run_file(b'GGUF' + b'\x03')

    def test_empty_file(self):
        with self.assertRaisesRegex(ValueError, 'bounds'):
            self.run_file(b'')

    def test_data_start_beyond_eof(self):
        with self.assertRaisesRegex(ValueError, 'data start beyond EOF'):
            self.run_file(fixture([], [('general.alignment', 1024)]))

    def test_truncated_tensor_directory(self):
        truncated = fixture([('blk.0.attn_q.weight', 14)])[:40]
        with self.assertRaisesRegex(ValueError, 'directory count|bounds'):
            self.run_file(truncated)


if __name__ == '__main__':
    unittest.main()
