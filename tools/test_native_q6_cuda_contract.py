"""Static Q6_K source-dispatch regression; does NOT claim CUDA compiled or executed.

The former opt-in Q6 implementation had Fmt<14> and gate/up Q6, but no
Q6_K down type, no Q6 row byte geometry, and no single-matrix MMVQ instantiation.
This test guards the three dispatch contracts against being silently dropped.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CUDA = (ROOT / 'src/kernels/cuda/iq_kernels.cu').read_text()
GROUP = (ROOT / 'src/kernels/native_grouped_parity.cpp').read_text()
MMQ = (ROOT / 'src/prefill/moe_mmq.cu').read_text()
CMAKE = (ROOT / 'CMakeLists.txt').read_text()


class Q6CudaContract(unittest.TestCase):
    def test_opt_in_not_default(self):
        self.assertRegex(CMAKE, r'option\(STRATA_Q6K_EXPERTS[^\n]*\bOFF\)')
        self.assertIn('if(STRATA_Q6K_EXPERTS)', CMAKE)

    def test_requires_mmq_kquants(self):
        self.assertRegex(CMAKE, r'if\(NOT STRATA_MMQ_KQUANTS\)')
        self.assertIn('Native Q6_K prefill requires', CMAKE)

    def test_q6_block_size(self):
        self.assertIn('sizeof(block_q6_K) == 210', CUDA)

    def test_q6_gate_up_and_down(self):
        self.assertRegex(CUDA, r'#ifdef STRATA_Q6K_EXPERTS\s*#define STRATA_GU_FMTS\(X\)[^\n]*X\(14\)')
        self.assertRegex(CUDA, r'#ifdef STRATA_Q6K_EXPERTS\s*#define STRATA_D_FMTS\(X\)[^\n]*X\(14\)')

    def test_q6_mmvq_dispatch(self):
        self.assertRegex(CUDA, r'#define STRATA_MMVQ_FMTS\(X\)[^\n]*X\(14\)')
        self.assertIn('STRATA_MMVQ_FMTS(STRATA_MMVQ)', CUDA)

    def test_q6_row_stride(self):
        self.assertRegex(CUDA, r'case 14: return \(size_t\) \(n / 256\) \* sizeof\(block_q6_K\)')

    def test_dot_and_dequant(self):
        self.assertIn('template<> struct Fmt<14>', CUDA)
        self.assertIn('vec_dot_q6_K_q8_1(v, y, kbx, iqs)', CUDA)
        self.assertIn('case 14: dq_q6_k(vx, ibs, y, tid);', CUDA)

    def test_prefill_q6_supported(self):
        self.assertIn('case GGML_TYPE_Q6_K: mul_mat_q_case<GGML_TYPE_Q6_K>', MMQ)

    def test_q6_grouped_parity_includes_down(self):
        self.assertRegex(GROUP, r'14,\s*// Q6_K down')
        self.assertIn('for (int dt :', GROUP)


if __name__ == '__main__':
    unittest.main()
