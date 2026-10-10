"""Source-only contract: native head/embedding must audit all shards before CUDA."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class HeadAndEmbeddingPreflight(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (ROOT / 'src/core/native_head.cpp').read_text(encoding='utf8')
        cls.reader = (ROOT / 'include/strata/artifact/gguf_reader.hpp').read_text(encoding='utf8')
        cls.dense = (ROOT / 'src/core/native_dense.cpp').read_text(encoding='utf8')

    def test_head_preflight_before_first_cuda_allocation(self):
        head = self.cpp.split('bool NativeHead::load(', 1)[1].split('bool NativeHead::run(', 1)[0]
        self.assertLess(head.index('validate_native_model_payloads(model)'), head.index('cudaMalloc('))
        self.assertIn('if (!tensor)', head)
        self.assertLess(head.index('if (!tensor)'), head.index('model.shard(at)'))

    def test_embedding_preflight_before_any_cuda_allocation(self):
        embed = self.cpp.split('bool NativeEmbed::load(', 1)[1].split('void NativeEmbed::gather_dev(', 1)[0]
        self.assertLess(embed.index('validate_native_model_payloads(model)'), embed.index('cudaHostAlloc('))
        self.assertLess(embed.index('validate_native_model_payloads(model)'), embed.index('cudaMalloc('))
        self.assertLess(embed.index('if (!t)'), embed.index('model.shard(at)'))
        self.assertIn('native_embedding_checked_bytes', embed)

    def test_head_embedding_and_dense_share_identical_payload_audit(self):
        self.assertEqual(self.cpp.count('strata::validate_native_model_payloads(model);'), 2)
        self.assertEqual(self.dense.count('strata::validate_native_model_payloads(model);'), 2)
        self.assertIn('validate_native_tensor_layout(model.shard(i));', self.reader)

    def test_signed_dimensions_and_unbounded_token_rejected(self):
        self.assertIn('n_vocab > INT32_MAX', self.cpp)
        self.assertIn('token < 0 || token >= n_vocab_', self.cpp)
        self.assertIn('native embedding: table byte count overflow', self.reader)

if __name__ == '__main__':
    unittest.main()
