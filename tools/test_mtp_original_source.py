"""Mocked GGUF tensors and small memory slices: no CUDA, real weights, gguf-py."""
from __future__ import annotations

import tempfile
import subprocess
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np

from tools import mtp_source_contract as c, mtp_original_rt as converter
from tools.mtp_runtime_contract import EXPERT_NAMES, Q8_NAMES
from tools.mtp_rt_validator import validate_runtime


def tensor(name, dtype, data):
    return SimpleNamespace(name=name, tensor_type=dtype, data=data)


def bf(values):
    return (np.asarray(values, dtype=np.float32).view(np.uint32) >> 16).astype(np.uint16)


def q8(values):
    arr = np.asarray(values, dtype=np.float32).reshape(-1, 32)
    d = np.maximum(np.abs(arr).max(axis=1) / 127.0, 1e-6).astype('<f2')
    quantized = np.rint(arr / d.astype(np.float32)[:, None]).clip(-127, 127).astype(np.int8)
    out = np.empty((len(arr), 34), dtype=np.uint8)
    out[:, :2] = d.view(np.uint8).reshape(-1, 2)
    out[:, 2:] = quantized.view(np.uint8)
    return out.reshape(-1)


def mini(expert_kind=30, dense_kind=30):
    count, ff, h = 2, 64, 64
    gate = np.arange(count * 2 * ff * h, dtype=np.float32).reshape(count, 2 * ff, h) / 2048
    down = np.arange(count * h * ff, dtype=np.float32).reshape(count, h, ff) / 2048
    pack = lambda x: bf(x) if expert_kind == 30 else np.stack([
        q8(row).reshape(-1) for row in x.reshape(-1, h if x.shape[-1] == h else ff)
    ]).reshape(x.shape[:-1] + (x.shape[-1] // 32 * 34,))
    data = [tensor(EXPERT_NAMES[0], expert_kind, pack(gate)),
            tensor(EXPERT_NAMES[1], expert_kind, pack(down))]
    for short in sorted(Q8_NAMES):
        x = np.arange(64, dtype=np.float32).reshape(2, 32) / 50
        data.append(tensor('mtp.layers.0.' + short, dense_kind,
                           bf(x) if dense_kind == 30 else q8(x).reshape(2, 34)))
    data.append(tensor('mtp.layers.0.norm.weight', 0, np.array([0, 1], dtype=np.float32)))
    return SimpleNamespace(tensors=data)


def toy_q2(x):
    """A valid Q2_0 block writer for small integration tests."""
    arr = x.reshape(-1, 64)
    d = np.maximum(np.abs(arr).max(axis=1) / 2, 0.0001).astype('<f2')
    code = np.rint(arr / d.astype(np.float32)[:, None]).clip(-1, 2).astype(np.uint8) + 1
    code = code.reshape(-1, 16, 4)
    merged = code[:, :, 0] | code[:, :, 1] << 2 | code[:, :, 2] << 4 | code[:, :, 3] << 6
    blocks = np.empty((len(arr), 18), dtype=np.uint8)
    blocks[:, :2] = d.view(np.uint8).reshape(-1, 2)
    blocks[:, 2:] = merged
    return blocks.reshape(-1)


def toy_blob(gu, dn):
    inter = gu.reshape(128, 18)
    inter2 = np.empty_like(inter)
    inter2[0::2] = inter[:64]
    inter2[1::2] = inter[64:]
    return b''.join((inter2[:, 2:].tobytes(), dn.reshape(64, 18)[:, 2:].tobytes(),
                     inter2[:, :2].tobytes(), dn.reshape(64, 18)[:, :2].tobytes()))


class OriginalSourceContractTest(unittest.TestCase):
    def test_accept_source_bf16(self):
        with mock.patch.object(c, 'H', 64), mock.patch.object(c, 'FF', 64), mock.patch.object(c, 'NE', 2):
            self.assertEqual(len(c.source_contract(mini().tensors)), len(Q8_NAMES) + 3)

    def test_accept_source_q8(self):
        with mock.patch.object(c, 'H', 64), mock.patch.object(c, 'FF', 64), mock.patch.object(c, 'NE', 2):
            c.source_contract(mini(8, 8).tensors)

    def test_wrong_expert_format(self):
        src = mini()
        src.tensors[0].tensor_type = 42
        with self.assertRaisesRegex(ValueError, 'expected source BF16'):
            c.source_contract(src.tensors)

    def test_source_bad_geometry(self):
        src = mini()
        src.tensors[0].data = src.tensors[0].data[..., :-1]
        with self.assertRaisesRegex(ValueError, 'geometry'):
            with mock.patch.object(c, 'H', 64), mock.patch.object(c, 'FF', 64), mock.patch.object(c, 'NE', 2):
                c.source_contract(src.tensors)

    def test_missing_projection(self):
        src = mini()
        src.tensors = [t for t in src.tensors if not t.name.endswith('fc_hidden.weight')]
        with self.assertRaisesRegex(ValueError, 'missing MTP dense'):
            with mock.patch.object(c, 'H', 64), mock.patch.object(c, 'FF', 64), mock.patch.object(c, 'NE', 2):
                c.source_contract(src.tensors)

    def test_q8_decode_exact(self):
        src = q8(np.array([1, -2, 3, -4] * 8, dtype=np.float32)).reshape(1, 34)
        got = c.q8_to_f32(src, logical_width=32)
        np.testing.assert_allclose(got, np.array([[1, -2, 3, -4] * 8], dtype=np.float32), atol=0.06)

    def test_bf16_decoder(self):
        np.testing.assert_array_equal(c.bf16_to_f32(bf([1, -2, 0, 3.5])), [1, -2, 0, 3.5])

    def test_invalid_q8_scale(self):
        src = q8(np.zeros(32, dtype=np.float32))
        src[:2] = np.array([255, 127], dtype=np.uint8)
        with self.assertRaisesRegex(ValueError, 'non-finite'):
            c.q8_to_f32(src, logical_width=32)

    def test_explicit_lossy_opt_in_required(self):
        script = Path(converter.__file__)
        result = subprocess.run([sys.executable, str(script), '--gguf', 'source.gguf',
                                 '--out', 'output', '--experts', 'q2_0'],
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn('--allow-lossy-expert-conversion', result.stderr)

    def test_no_preexisting_runtime_clobber(self):
        script = Path(converter.__file__)
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp, 'original.gguf')
            source.write_bytes(b'not a real gguf')
            output = Path(tmp, 'runtime')
            output.mkdir()
            marker = output / 'kept.txt'
            marker.write_text('do not delete')
            result = subprocess.run([sys.executable, str(script), '--gguf', str(source),
                                     '--out', str(output), '--experts', 'q2_0',
                                     '--allow-lossy-expert-conversion'],
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(marker.read_text(), 'do not delete')

    def test_integrated_small_runtime(self):
        for expert_kind, dense_kind in ((30, 30), (8, 8)):
            with self.subTest(expert=expert_kind, dense=dense_kind), tempfile.TemporaryDirectory() as tmp:
                src = mini(expert_kind, dense_kind)
                dest = Path(tmp)
                patches = [mock.patch.object(obj, attr, val)
                           for obj in (c, converter) for attr, val in (('H', 64), ('FF', 64), ('NE', 2))]
                with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5]:
                    result = converter.prepare(src, dest, toy_q2, toy_blob,
                                               lambda x: q8(x).tobytes(), sample_count=1)
                self.assertEqual(result['expert_count'], 2)
                self.assertEqual(result['runtime_expert_quantization'], 'Q2_0')
                self.assertGreater((dest / 'dense.bin').stat().st_size, 0)
                self.assertEqual((dest / 'experts.bin').stat().st_size, 2 * 3456)
                self.assertEqual(len(validate_runtime(dest, expected_expert_bytes=2 * 3456)), len(Q8_NAMES) + 1)

    def test_index_reject_out_of_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp)
            (dest / 'experts.bin').write_bytes(b'1234')
            (dest / 'dense.bin').write_bytes(b'1234')
            (dest / 'dense.txt').write_text('fc_embedding.weight q8_0 2 32 0 68\n')
            with self.assertRaisesRegex(ValueError, 'range'):
                validate_runtime(dest, expected_expert_bytes=4)


if __name__ == '__main__':
    unittest.main()
