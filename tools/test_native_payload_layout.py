"""Native Q6_K / Q8_0 payload layout regression (header-only; no CUDA or weights)."""
import struct
import tempfile
import unittest
from pathlib import Path

from tools.gguf_reader import GGUFFile
from tools.model_compat import inspect


def s(value):
    value = value.encode()
    return struct.pack('<Q', len(value)) + value


def fixture(path, *, width=256, offset=448, last_bytes=102, height=2, q6_type=14):
    b = bytearray(b'GGUF' + struct.pack('<IQQ', 3, 2, 0))
    b += s('blk.0.ffn_gate_shexp.weight') + struct.pack('<IQQIQ', 2, width, height, q6_type, 0)
    b += s('blk.0.ffn_up_shexp.weight') + struct.pack('<IQQIQ', 2, 32, 3, 8, offset)
    b.extend(bytes(-len(b) % 32))
    b.extend(bytes(max(420, offset + last_bytes)))
    path.write_bytes(b)


class NativePayloadLayoutTests(unittest.TestCase):
    def run_variant(self, **kwargs):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'Qwen3.8-Flash-Next-Q6_K.gguf'
            fixture(p, **kwargs)
            gguf = GGUFFile(p)
            gguf.validate_native_payload_layout()
            return inspect([p])

    def test_valid_q6_and_q8(self):
        result = self.run_variant()
        self.assertEqual(result['tensor_count'], 2)

    def test_bad_q6_row_width(self):
        with self.assertRaisesRegex(ValueError, 'block geometry'):
            self.run_variant(width=128)

    def test_overlap_at_aligned_offset(self):
        with self.assertRaisesRegex(ValueError, 'overlapping tensor payloads'):
            self.run_variant(offset=416)

    def test_same_offset(self):
        with self.assertRaisesRegex(ValueError, 'overlapping tensor payloads'):
            self.run_variant(offset=0)

    def test_unaligned_q8_offset(self):
        with self.assertRaisesRegex(ValueError, 'unaligned tensor offset'):
            self.run_variant(offset=4)

    def test_truncated_q8(self):
        with self.assertRaisesRegex(ValueError, 'truncated tensor'):
            self.run_variant(last_bytes=20)

    def test_zero_row_width(self):
        with self.assertRaisesRegex(ValueError, 'block geometry'):
            self.run_variant(width=0)

    def test_oversized_product(self):
        # Python int is unbounded, but the native C++ reader detects uint64 overflow.
        # This fixture is rejected because its tensor cannot fit the payload.
        with self.assertRaisesRegex(ValueError, 'truncated tensor'):
            self.run_variant(height=(1 << 64) - 1)

    def test_unknown_type_rejected_for_native(self):
        with self.assertRaisesRegex(ValueError, 'block geometry'):
            self.run_variant(q6_type=5000)


if __name__ == '__main__':
    unittest.main()
