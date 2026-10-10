"""Native expert MTP: lossless bitstream/manifest and old Q2 backward compatibility."""
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from tools import mtp_native_layout as layout, mtp_original_rt as converter
from tools import mtp_source_contract as source
from tools.test_mtp_original_source import mini, q8, bf
from tools.mtp_rt_validator import validate_runtime


def native_mini(expert_kind=30, down_kind=None):
    data = mini(expert_kind, 30)
    if down_kind is not None and down_kind != expert_kind:
        t = data.tensors[1]
        # mini Q8 uses physical 68 for its down 64, so reconstruct from BF16.
        if down_kind == 8:
            raw = ((t.data.astype(np.uint32) << 16).view(np.float32))
            t.data = q8(raw).reshape(2, 64, 68)
        else:
            from tools.mtp_source_contract import q8_to_f32
            t.data = bf(q8_to_f32(t.data, logical_width=64))
        t.tensor_type = down_kind
    return data


class NativeRuntimeTest(unittest.TestCase):
    def patch_sizes(self):
        from contextlib import ExitStack
        stack = ExitStack()
        for target in (source, converter):
            stack.enter_context(mock.patch.object(target, 'NE', 2))
            stack.enter_context(mock.patch.object(target, 'H', 64))
            stack.enter_context(mock.patch.object(target, 'FF', 64))
        return stack

    def test_geometry_layout(self):
        self.assertEqual(layout.native_layout('bf16', 'bf16', 2, 64, 64)['total_bytes'], 49152)
        self.assertEqual(layout.native_layout('q8_0', 'q8_0', 2, 64, 64)['total_bytes'], 26112)

    def test_each_kind_lossless(self):
        for kind in (30, 8):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                src = mini(kind, 30)
                with self.patch_sizes():
                    summary = converter.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())
                self.assertEqual(summary['conversion'], 'NATIVE_LOSSLESS_EXPERTS')
                self.assertEqual(summary['sample_relative_rms_error'], 0.0)
                recorded = (Path(tmp) / 'experts.bin').read_bytes()
                expected = b''.join(np.asarray(t.data[i]).tobytes() for i in range(2)
                                    for t in src.tensors[:2])
                self.assertEqual(recorded, expected)
                self.assertEqual(len(validate_runtime(Path(tmp), native_geometry=(2, 64, 64))), 11)
                parsed = layout.validate_native_manifest(Path(tmp), len(recorded), n=2, h=64, ff=64)
                self.assertEqual(parsed['gate_kind'], 'bf16' if kind == 30 else 'q8_0')

    def test_mixed_expert_formats(self):
        with tempfile.TemporaryDirectory() as tmp, self.patch_sizes():
            src = native_mini(8, 30)
            result = converter.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())
            self.assertEqual(result['source_expert_quantization']['down'], 'BF16')
            self.assertEqual(layout.validate_native_manifest(Path(tmp), (Path(tmp) / 'experts.bin').stat().st_size,
                                                              n=2, h=64, ff=64)['down_kind'], 'bf16')

    def test_size_tamper(self):
        with tempfile.TemporaryDirectory() as tmp, self.patch_sizes():
            converter.prepare_native(mini(), Path(tmp), lambda x: q8(x).tobytes())
            blob = Path(tmp, 'experts.bin')
            with blob.open('ab') as f:
                f.write(b'X')
            with self.assertRaisesRegex(ValueError, 'size mismatch'):
                validate_runtime(Path(tmp), native_geometry=(2, 64, 64))

    def test_manifest_tamper_no_q2_fallback(self):
        with tempfile.TemporaryDirectory() as tmp, self.patch_sizes():
            converter.prepare_native(mini(), Path(tmp), lambda x: q8(x).tobytes())
            (Path(tmp) / 'experts.txt').write_text('mtp_native_experts_v1 q2_0 bf16 2 64 64\n')
            with self.assertRaisesRegex(ValueError, 'invalid native expert format'):
                validate_runtime(Path(tmp), native_geometry=(2, 64, 64))

    def test_native_cli_rejects_lossy_flag(self):
        import subprocess, sys
        result = subprocess.run([sys.executable, str(Path(converter.__file__)), '--gguf', 'none.gguf',
                                 '--out', 'none', '--experts', 'native', '--allow-lossy-expert-conversion'],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 2)
        self.assertIn('lossless', result.stderr)

    def test_bad_q8_scale(self):
        with tempfile.TemporaryDirectory() as tmp, self.patch_sizes():
            src = mini(8, 30)
            src.tensors[0].data[0, 0, 0:2] = [255, 127]
            with self.assertRaisesRegex(ValueError, 'non-finite Q8_0'):
                converter.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())

    def test_symlink_manifest(self):
        with tempfile.TemporaryDirectory() as tmp, self.patch_sizes():
            converter.prepare_native(mini(), Path(tmp), lambda x: q8(x).tobytes())
            folder = Path(tmp)
            original = folder / 'original-manifest'
            (folder / 'experts.txt').rename(original)
            (folder / 'experts.txt').symlink_to(original)
            with self.assertRaisesRegex(ValueError, 'symlinked'):
                validate_runtime(folder, native_geometry=(2, 64, 64))


# A CPU oracle for the CUDA kernel's two GEMV stages, using the EXACT bytes
# emitted by the production writer. No model, GPU or CUDA runtime is required.
class NativeMathOracleTest(unittest.TestCase):
    def test_bf16_and_q8_gated_moe(self):
        from tools.mtp_source_contract import q8_to_f32, bf16_to_f32
        for kind in (30, 8):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                src = mini(kind, 30)
                with NativeRuntimeTest().patch_sizes():
                    converter.prepare_native(src, Path(tmp), lambda x: q8(x).tobytes())
                raw = (Path(tmp) / 'experts.bin').read_bytes()
                md = layout.validate_native_manifest(Path(tmp), len(raw), n=2, h=64, ff=64)
                x = np.linspace(-0.25, 0.25, 64, dtype=np.float32)
                for expert in (0, 1):
                    off = expert * md['expert_bytes']
                    gu_bytes = raw[off:off + md['gate_bytes']]
                    dn_bytes = raw[off + md['gate_bytes']:off + md['expert_bytes']]
                    if kind == 30:
                        gu = bf16_to_f32(np.frombuffer(gu_bytes, dtype='<u2').reshape(128, 64))
                        dn = bf16_to_f32(np.frombuffer(dn_bytes, dtype='<u2').reshape(64, 64))
                    else:
                        gu = q8_to_f32(np.frombuffer(gu_bytes, dtype='u1').reshape(128, 68), logical_width=64)
                        dn = q8_to_f32(np.frombuffer(dn_bytes, dtype='u1').reshape(64, 68), logical_width=64)
                    gate = gu[:64] @ x
                    up = gu[64:] @ x
                    mid = (gate / (1 + np.exp(-gate))) * up
                    out = dn @ mid
                    original_gu = (bf16_to_f32(src.tensors[0].data[expert]) if kind == 30 else
                                   q8_to_f32(src.tensors[0].data[expert], logical_width=64))
                    original_dn = (bf16_to_f32(src.tensors[1].data[expert]) if kind == 30 else
                                   q8_to_f32(src.tensors[1].data[expert], logical_width=64))
                    orig_gate = original_gu[:64] @ x
                    orig_up = original_gu[64:] @ x
                    expected = original_dn @ ((orig_gate / (1 + np.exp(-orig_gate))) * orig_up)
                    np.testing.assert_allclose(out, expected, rtol=1e-5, atol=1e-5)

if __name__ == '__main__':
    unittest.main()
