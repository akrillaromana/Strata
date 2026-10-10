"""Q8_1 fused GPU SwiGLU source and CPU-only quantizer contract.

This does not claim CUDA has compiled or that GPU parity was executed.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MMVQ = (ROOT / "src/kernels/cuda/native_mmvq.cu").read_text()
GROUPED = (ROOT / "src/kernels/cuda/iq_kernels.cu").read_text()
CMAKE = (ROOT / "CMakeLists.txt").read_text()


class SwigluQ8Contract(unittest.TestCase):
    def test_native_uses_finite_scale(self):
        method = MMVQ.split("native_swiglu_quantize_q8_1_kernel(")[1].split("__launch_bounds__")[0]
        self.assertIn("q8_1_finite(amax / 127.0f)", method)

    def test_native_uses_saturating_int8(self):
        method = MMVQ.split("native_swiglu_quantize_q8_1_kernel(")[1].split("__launch_bounds__")[0]
        self.assertIn("q8_1_quant(xi, d, amax)", method)
        self.assertIn("q8_1_ds(d, sum)", method)
        self.assertNotIn("roundf(xi / d)", method)

    def test_grouped_fused_uses_same_quantizer(self):
        self.assertIn('q8_1_store(xi, y, (long long) blockIdx.x * 32 + lane);', GROUPED)
        self.assertIn('const float d = q8_1_finite(amax / 127.0f)', GROUPED)
        self.assertIn('const int8_t q = q8_1_quant(xi, d, amax)', GROUPED)

    def test_grouped_output_stride(self):
        self.assertIn('block_q8_1* y = hq + (size_t) (c0 + warp) * hb;', GROUPED)
        self.assertRegex(GROUPED, r'const long long ib = i / 32, iqs = i % 32;')

    def test_native_shape_guard(self):
        self.assertIn('native_mmvq_shape_ok(n_in, ncols, block_elems)', MMVQ)
        self.assertIn('n_in * ncols exceeds 32-bit', MMVQ)
        header = (ROOT / 'include/strata/kernels/native_mmvq_shape.hpp').read_text()
        self.assertIn('std::numeric_limits<int>::max() / ncols', header)

    def test_cpu_source_is_registered(self):
        self.assertIn('native_q8_swiglu_shape_test.cpp', CMAKE)


if __name__ == "__main__":
    unittest.main()
