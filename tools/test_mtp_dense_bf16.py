"""Regression: native MTP BF16 dense is preserved from GGUF through runtime index.

Run without CUDA, real models or mutable E:/R: working folders.
"""
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from tools import mtp_original_rt as conv, mtp_source_contract as source
from tools.test_mtp_original_source import mini, q8
from tools.mtp_rt_validator import validate_runtime
from tools.mtp_runtime_contract import Q8_NAMES


class DenseBf16NativeTest(unittest.TestCase):
    def patched(self):
        from contextlib import ExitStack
        stack = ExitStack()
        for target in (source, conv):
            for attr, val in (('NE', 2), ('H', 64), ('FF', 64)):
                stack.enter_context(mock.patch.object(target, attr, val))
        return stack

    def test_bf16_dense_lossless_native(self):
        with tempfile.TemporaryDirectory() as tmp, self.patched():
            src = mini(30, 30)
            summary = conv.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())
            self.assertTrue(summary['native_dense_bf16_preserved'])
            self.assertEqual(summary['conversion'], 'NATIVE_LOSSLESS_EXPERTS')
            dense_entries = validate_runtime(Path(tmp), native_geometry=(2, 64, 64))
            self.assertEqual(len(dense_entries), len(Q8_NAMES) + 1)
            raw = Path(tmp, 'dense.bin').read_bytes()
            for item in dense_entries:
                if item['name'] not in Q8_NAMES:
                    continue
                self.assertEqual(item['kind'], 'bf16')
                target = next(t for t in src.tensors if t.name.endswith(item['name']))
                self.assertEqual(raw[item['start']:item['end']], target.data.tobytes())

    def test_q8_stays_bit_exact(self):
        with tempfile.TemporaryDirectory() as tmp, self.patched():
            src = mini(8, 8)
            conv.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())
            entries = validate_runtime(Path(tmp), native_geometry=(2, 64, 64))
            raw = Path(tmp, 'dense.bin').read_bytes()
            for item in entries:
                if item['name'] not in Q8_NAMES:
                    continue
                self.assertEqual(item['kind'], 'q8_0')
                target = next(t for t in src.tensors if t.name.endswith(item['name']))
                self.assertEqual(raw[item['start']:item['end']], target.data.tobytes())

    def test_mixed_source_dense(self):
        with tempfile.TemporaryDirectory() as tmp, self.patched():
            src = mini(30, 30)
            proj = next(t for t in src.tensors if t.name.endswith('fc_embedding.weight'))
            proj.data = q8(np.ones((2, 32), dtype=np.float32)).reshape(2, 34)
            proj.tensor_type = 8
            conv.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())
            entries = validate_runtime(Path(tmp), native_geometry=(2, 64, 64))
            mapping = {t['name']: t['kind'] for t in entries}
            self.assertEqual(mapping['fc_embedding.weight'], 'q8_0')
            self.assertEqual(mapping['fc_hidden.weight'], 'bf16')

    def test_legacy_q2_keeps_q8_projection(self):
        # Only the native route preserves BF16 dense; existing lossy q2 runtime
        # retains the previous Q8_0 layout used by earlier CUDA builds.
        from tools.test_mtp_original_source import toy_q2, toy_blob
        with tempfile.TemporaryDirectory() as tmp, self.patched():
            src = mini(30, 30)
            conv.prepare(src, Path(tmp), toy_q2, toy_blob,
                         lambda x: q8(x).tobytes(), sample_count=0)
            self.assertEqual({t['kind'] for t in validate_runtime(Path(tmp), expected_expert_bytes=2 * 3456)
                              if t['name'] in Q8_NAMES}, {'q8_0'})

    def test_bad_bf16_dense_not_written(self):
        with tempfile.TemporaryDirectory() as tmp, self.patched():
            src = mini(30, 30)
            t = next(t for t in src.tensors if t.name.endswith('fc_embedding.weight'))
            t.data[0, 0] = np.uint16(0x7fc0)  # NaN BF16
            with self.assertRaisesRegex(ValueError, 'non-finite'):
                conv.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())

    def test_manifest_reject_wrong_required_format(self):
        with tempfile.TemporaryDirectory() as tmp, self.patched():
            conv.prepare_native(mini(), Path(tmp), lambda x: q8(x).tobytes())
            f = Path(tmp, 'dense.txt')
            contents = f.read_text()
            f.write_text(contents.replace('fc_embedding.weight bf16', 'fc_embedding.weight f32'))
            with self.assertRaisesRegex(ValueError, 'size|BF16/Q8_0'):
                validate_runtime(Path(tmp), native_geometry=(2, 64, 64))


if __name__ == '__main__':
    unittest.main()
