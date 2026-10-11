"""CPU-only IQ3_S / Q6_K / Q8_0 kernel entry contract source regression checks."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CUDA = (ROOT / "src/kernels/cuda/iq_kernels.cu").read_text()
HEADER = (ROOT / "include/strata/kernels/iq_launch_safety.hpp").read_text()


class IQEntrySafetyTests(unittest.TestCase):
    def test_iq_entry_includes_shared_checked_contract(self):
        self.assertIn('#include "strata/kernels/iq_launch_safety.hpp"', CUDA)

    def test_iq_matrix_dimensions_checked_before_row_bytes(self):
        body = CUDA.split("void iq_mmvq(", 1)[1].split("void iq_dequant_f16(", 1)[0]
        self.assertLess(body.index("iq_mmvq_shape_ok"), body.index("iq_row_bytes(t, n_in)"))
        self.assertIn("n_out", body)

    def test_iq_does_not_exit_on_unsupported_format(self):
        body = CUDA.split("void iq_mmvq(", 1)[1].split("void iq_dequant_f16(", 1)[0]
        self.assertIn('throw std::invalid_argument("iq_mmvq: type is not supported', body)
        self.assertNotIn("std::exit", body)

    def test_quantizer_checks_before_signed_multiplication(self):
        body = CUDA.split("void quantize_q8_1_rows(", 1)[1].split("void iq_mmvq(", 1)[0]
        self.assertLess(body.index("iq_quantize_rows_shape_ok"), body.index("n_rows * n_cols"))

    def test_groups_use_checked_offsets(self):
        body = CUDA.split("NativeExpertLayout native_expert_layout(", 1)[1].split("size_t native_expert_scratch_bytes", 1)[0]
        self.assertIn("iq_expert_offsets", body)
        self.assertIn("native_expert_supported", body)

    def test_groups_no_signed_product_undefined_behavior(self):
        body = CUDA.split("bool native_expert_supported(", 1)[1].split("NativeExpertLayout native_expert_layout", 1)[0]
        self.assertNotRegex(body, r"n_ff\s*\*\s*n_embd")
        self.assertIn("n_embd % 256 == 0", body)

    def test_scratch_checked_for_multiple_additions(self):
        body = CUDA.split("size_t native_expert_scratch_bytes(", 1)[1].split("#if defined(STRATA_HIP_GFX906)", 1)[0]
        self.assertIn("iq_expert_scratch_bytes_checked", body)
        self.assertIn("sizeof(block_q8_1) == 36", body)

    def test_no_cuda_dependency_in_geometry(self):
        self.assertNotIn("cuda_runtime.h", HEADER)
        self.assertIn("std::numeric_limits<int>", HEADER)

    def test_quantizer_keeps_default_cuda_stream_supported(self):
        body = CUDA.split("void quantize_q8_1_rows(", 1)[1].split("void iq_mmvq(", 1)[0]
        self.assertNotIn("!stream", body)

    def test_grouped_cuda_contract_has_source_associations(self):
        self.assertIn("iq_expert_offsets(L.gu_row, L.d_row, n_embd, n_ff)", CUDA)
        self.assertIn("iq_expert_scratch_bytes_checked(cap, n_ff)", CUDA)


if __name__ == "__main__":
    unittest.main()
