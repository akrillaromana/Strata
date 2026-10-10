"""Source-only native dense complete-shard contract; GPU not compiled or run."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeDenseSplitContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'src/core/native_dense.cpp').read_text(encoding='utf-8')
        cls.reader = (ROOT / 'include/strata/artifact/gguf_reader.hpp').read_text(encoding='utf-8')

    def test_both_discovery_and_loading_use_complete_model(self):
        self.assertEqual(self.source.count('const strata::GgufModel model(shards);'), 2)

    def test_both_paths_verify_architecture(self):
        self.assertIn('strata::check_architecture(model.meta())', self.source)
        self.assertEqual(self.source.count('strata::check_architecture(model.meta())'), 2)

    def test_discovery_refuses_truncated_native_tensor(self):
        self.assertIn('model.in_bounds(tensor, i)', self.source)

    def test_upload_keeps_all_tensor_span_validation(self):
        self.assertEqual(self.source.count('strata::validate_native_model_payloads(model);'), 2)
        self.assertIn('validate_native_tensor_layout(model.shard(i));', self.reader)
        self.assertIn('overlapping tensor payloads', self.reader)
        self.assertIn('truncated tensor payload', self.reader)
        self.assertIn('tensor_payload_bytes(t)', self.reader)

    def test_metadata_contract_handles_llama_split_types(self):
        self.assertIn('MetaType::U16', self.reader)
        self.assertIn('MetaType::I32', self.reader)
        self.assertIn('duplicate metadata key', self.reader)

    def test_native_q6_q8_gpu_dispatch_not_removed(self):
        kernel = (ROOT / 'src/kernels/cuda/native_mmvq.cu').read_text(encoding='utf-8')
        self.assertIn('case 14: native_q6_k_mmvq', kernel)
        self.assertIn('case 8: native_q8_0_mmvq', kernel)


if __name__ == '__main__':
    unittest.main()
