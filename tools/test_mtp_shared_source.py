"""Shared-only MTP source safety. Small synthetic GGUF arrays, no model weights."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np

from tools import mtp_original_rt, mtp_source_contract, mtp_shared_source
from tools.test_mtp_original_source import mini, toy_q2, toy_blob, q8
from tools.mtp_runtime_contract import EXPERT_NAMES


def split_source(*, kind=30):
    reader = mini(expert_kind=kind, dense_kind=kind)
    shared = [t for t in reader.tensors if str(t.name) in mtp_shared_source.SHARED_PROJECTIONS]
    for t in shared:
        shape = (64, 68) if kind == 8 else (64, 64)
        t.data = np.ones(shape, dtype=np.uint8 if kind == 8 else np.uint16)
        if kind == 8:
            t.data = q8(np.ones(64 * 64, dtype=np.float32)).reshape(shape)
    base = [t for t in reader.tensors if str(t.name) not in mtp_shared_source.SHARED_PROJECTIONS]
    return SimpleNamespace(tensors=base), SimpleNamespace(tensors=shared)


class MtpSharedSourceTests(unittest.TestCase):
    def join(self, base, shared):
        with mock.patch.object(mtp_source_contract, 'H', 64), \
             mock.patch.object(mtp_source_contract, 'FF', 64), \
             mock.patch.object(mtp_source_contract, 'NE', 2):
            return mtp_shared_source.join_shared(base, shared)

    def test_missing_shared_bf16(self):
        base, shared = split_source()
        result = self.join(base, shared)
        self.assertEqual(len(result.shared_added), 3)
        self.assertEqual(len(result.readers), 2)
        self.assertEqual(len(result.tensors), len(mini().tensors))

    def test_missing_shared_q8(self):
        base, shared = split_source(kind=8)
        self.assertEqual(len(self.join(base, shared).shared_added), 3)

    def test_mixed_source(self):
        base, shared = split_source()
        shared.tensors[0].tensor_type = 8
        shared.tensors[0].data = q8(np.ones(64 * 64, dtype=np.float32)).reshape(64, 68)
        self.assertEqual(len(self.join(base, shared).shared_added), 3)

    def test_missing_routed_expert_rejected(self):
        base, shared = split_source()
        base.tensors = [t for t in base.tensors if t.name != EXPERT_NAMES[0]]
        with self.assertRaisesRegex(ValueError, 'missing original MTP experts'):
            self.join(base, shared)

    def test_non_shared_tensor_rejected(self):
        base, shared = split_source()
        shared.tensors.append(base.tensors[0])
        with self.assertRaisesRegex(ValueError, 'not shared-only'):
            self.join(base, shared)

    def test_duplicate_name_rejected(self):
        base, shared = split_source()
        shared.tensors.append(shared.tensors[0])
        with self.assertRaisesRegex(ValueError, 'duplicate companion'):
            self.join(base, shared)

    def test_missing_projection_rejected(self):
        base, shared = split_source()
        shared.tensors.pop()
        with self.assertRaisesRegex(ValueError, 'misses shared'):
            self.join(base, shared)

    def test_bad_tensor_type_rejected(self):
        base, shared = split_source()
        shared.tensors[0].tensor_type = 42
        with self.assertRaisesRegex(ValueError, 'BF16/Q8_0'):
            self.join(base, shared)

    def test_bad_dimensions_rejected(self):
        base, shared = split_source()
        shared.tensors[0].data = np.zeros(32, dtype=np.uint16)
        with self.assertRaisesRegex(ValueError, 'physical tensor layout'):
            self.join(base, shared)

    def test_overlap_identical_and_new(self):
        base, shared = split_source()
        base.tensors.append(shared.tensors[0])
        result = self.join(base, shared)
        self.assertEqual(len(result.shared_added), 2)

    def test_overlap_different_payload_rejected(self):
        base, shared = split_source()
        copied = SimpleNamespace(name=shared.tensors[0].name,
                                 tensor_type=shared.tensors[0].tensor_type,
                                 data=shared.tensors[0].data.copy())
        copied.data.flat[0] ^= 1
        base.tensors.append(copied)
        with self.assertRaisesRegex(ValueError, 'conflicting shared tensor'):
            self.join(base, shared)

    def test_overlap_type_mismatch_rejected(self):
        base, shared = split_source()
        copied = SimpleNamespace(name=shared.tensors[0].name,
                                 tensor_type=8, data=np.zeros((64, 68), dtype=np.uint8))
        base.tensors.append(copied)
        with self.assertRaisesRegex(ValueError, 'conflicting shared tensor'):
            self.join(base, shared)

    def test_no_new_tensors_rejected(self):
        base, shared = split_source()
        base.tensors.extend(shared.tensors)
        with self.assertRaisesRegex(ValueError, 'contributes no missing'):
            self.join(base, shared)

    def test_allows_bf16_scalar_gate(self):
        base, shared = split_source()
        shared.tensors.append(SimpleNamespace(name='mtp.layers.0.mlp.shared_expert_gate.weight',
                                             tensor_type=30, data=np.ones(64, dtype=np.uint16)))
        self.assertEqual(len(self.join(base, shared).shared_added), 4)

    def test_companion_unrelated_optional_kind_rejected(self):
        base, shared = split_source()
        shared.tensors.append(SimpleNamespace(name='mtp.layers.0.mlp.shared_expert_gate.weight',
                                             tensor_type=8, data=np.zeros(64, dtype=np.uint8)))
        with self.assertRaisesRegex(ValueError, 'BF16 scalar gate'):
            self.join(base, shared)

    def test_companion_optional_scalar_wrong_length(self):
        base, shared = split_source()
        shared.tensors.append(SimpleNamespace(name='mtp.layers.0.mlp.shared_expert_gate.weight',
                                             tensor_type=30, data=np.ones(63, dtype=np.uint16)))
        with self.assertRaisesRegex(ValueError, 'physical tensor layout'):
            self.join(base, shared)

    def test_companion_q8_projection_truncated_block(self):
        base, shared = split_source(kind=8)
        shared.tensors[0].data = shared.tensors[0].data[:, :-1]
        with self.assertRaisesRegex(ValueError, 'physical tensor layout'):
            self.join(base, shared)

    def test_does_not_modify_original_tensor_lists(self):
        base, shared = split_source()
        original_names = [t.name for t in base.tensors]
        companion_names = [t.name for t in shared.tensors]
        joined = self.join(base, shared)
        self.assertEqual([t.name for t in base.tensors], original_names)
        self.assertEqual([t.name for t in shared.tensors], companion_names)
        self.assertTrue(any(n in joined.shared_added for n in companion_names))

    def test_primary_duplicates_rejected(self):
        base, shared = split_source()
        base.tensors.append(base.tensors[0])
        with self.assertRaisesRegex(ValueError, 'duplicate primary'):
            self.join(base, shared)

    def test_prepare_native_combined_runtime(self):
        base, shared = split_source()
        reader = self.join(base, shared)
        with tempfile.TemporaryDirectory() as temp:
            with mock.patch.object(mtp_source_contract, 'H', 64), mock.patch.object(mtp_source_contract, 'FF', 64), \
                 mock.patch.object(mtp_source_contract, 'NE', 2), mock.patch.object(mtp_original_rt, 'H', 64), \
                 mock.patch.object(mtp_original_rt, 'FF', 64), mock.patch.object(mtp_original_rt, 'NE', 2):
                result = mtp_original_rt.prepare_native(reader, Path(temp), lambda a: q8(a).tobytes())
            self.assertEqual(result['dense_tensor_count'], len(mini().tensors) - 2)
            self.assertGreater((Path(temp) / 'experts.bin').stat().st_size, 0)


if __name__ == '__main__':
    unittest.main()
