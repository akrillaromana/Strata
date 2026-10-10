"""Offline contract tests for MTP GGUF inputs, no gguf-py/CUDA/weights."""
from __future__ import annotations

import unittest
from types import SimpleNamespace

from tools.mtp_runtime_contract import packed_mtp_contract, EXPERT_NAMES, Q8_NAMES


def tensor(name, kind, shape):
    return SimpleNamespace(name=name, tensor_type=kind,
                           data=SimpleNamespace(shape=shape))


def complete():
    x = [tensor(EXPERT_NAMES[0], 42, (512, 1280, 720)),
         tensor(EXPERT_NAMES[1], 42, (512, 2560, 180))]
    x.extend(tensor('mtp.layers.0.' + name, 30, (64, 2560)) for name in sorted(Q8_NAMES))
    x.append(tensor('mtp.layers.0.norm.weight', 0, (2560,)))
    return x


class Contract(unittest.TestCase):
    def test_original_q2_source(self):
        packed_mtp_contract(complete())

    def test_bf16_expert_source_not_q2(self):
        for kind in (8, 30):
            x = complete()
            x[0].tensor_type = kind
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, 'NOT a direct BF16/Q8_0'):
                packed_mtp_contract(x)

    def test_missing_expert(self):
        with self.assertRaisesRegex(ValueError, 'missing routed experts'):
            packed_mtp_contract(complete()[1:])

    def test_expert_blob_geometry(self):
        x = complete()
        x[0].data.shape = (512, 1280, 2720)
        with self.assertRaisesRegex(ValueError, 'geometry'):
            packed_mtp_contract(x)

    def test_reject_duplicate(self):
        x = complete()
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            packed_mtp_contract(x + [x[0]])

    def test_required_projection(self):
        x = [t for t in complete() if t.name != 'mtp.layers.0.fc_embedding.weight']
        with self.assertRaisesRegex(ValueError, 'missing required dense projection'):
            packed_mtp_contract(x)

    def test_dense_already_q8_is_not_bf16(self):
        x = complete()
        x[2].tensor_type = 8
        with self.assertRaisesRegex(ValueError, 'unsupported GGML type'):
            packed_mtp_contract(x)

    def test_norm_must_be_vector(self):
        x = complete()
        x[-1].data.shape = (10, 256)
        with self.assertRaisesRegex(ValueError, 'norm vector'):
            packed_mtp_contract(x)

    def test_reject_path_like_tensor(self):
        x = complete()
        x[-1].name = 'mtp../../bad'
        with self.assertRaisesRegex(ValueError, 'safe mtp'):
            packed_mtp_contract(x)

    def test_bad_q8_geometry(self):
        x = complete()
        x[2].data.shape = (64, 33)
        with self.assertRaisesRegex(ValueError, 'Q8_0 rows'):
            packed_mtp_contract(x)


if __name__ == '__main__':
    unittest.main()
