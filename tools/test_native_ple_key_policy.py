"""Header-only native PLE pack policy, does not depend on gguf-py fixtures."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import iq_pack


class NativePleKeyPolicy(unittest.TestCase):
    def test_quantizations_explicitly_served_by_native_dense(self):
        for name in ("Q2_0", "Q8_0", "IQ3_XXS", "IQ4_XS"):
            with self.subTest(type=name):
                self.assertIn(name, iq_pack.NATIVE_PLE_KEY)
                self.assertFalse(iq_pack.needs_bf16("blk.1.ple_key.weight", name))

    def test_other_quantizations_still_require_conversion(self):
        for name in ("Q4_K", "Q5_K", "Q6_K", "IQ2_XS"):
            with self.subTest(type=name):
                self.assertTrue(iq_pack.needs_bf16("blk.1.ple_key.weight", name))

    def test_ple_value_is_not_misclassified_as_ple_key(self):
        self.assertTrue(iq_pack.needs_bf16("blk.1.ple_value.weight", "Q8_0"))
        self.assertTrue(iq_pack.needs_bf16("blk.1.ple_value.weight", "IQ4_XS"))

    def test_native_dense_dispatch_has_matching_type_ids(self):
        native = (ROOT / "src/core/native_dense.cpp").read_text(encoding="utf-8")
        native_mmvq = (ROOT / "src/kernels/cuda/native_mmvq.cu").read_text(encoding="utf-8")
        for type_id in ("42", "8", "18", "23"):
            with self.subTest(type_id=type_id):
                self.assertIn("tensor.type == " + type_id, native)
                self.assertRegex(native_mmvq, r"\b" + type_id + r"\b")


if __name__ == "__main__":
    unittest.main()
