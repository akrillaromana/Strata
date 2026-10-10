"""Source-level CUDA/HIP NativeEmbed wiring checks; GPU execution is NOT asserted."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = (ROOT / 'src/core/native_head.cpp').read_text()
HDR = (ROOT / 'include/strata/core/native_embed_allocation.hpp').read_text()


class NativeEmbedAllocationContract(unittest.TestCase):
    def test_uses_transaction(self):
        self.assertIn('NativeEmbedAllocation staging(', SRC)
        self.assertIn('staging.commit(host_, dev_);', SRC)

    def test_prevents_second_load(self):
        self.assertIn('if (host_ || dev_)', SRC)

    def test_fallback_on_alias_failure(self):
        self.assertIn('cudaHostGetDevicePointer(&alias, pinned, 0)', SRC)
        self.assertIn('staging.set_device_owned(gpu)', SRC)
        self.assertIn('staging.drop_host_after_copy()', SRC)

    def test_fallback_on_pinned_allocation_failure(self):
        self.assertIn('pinned_status == cudaSuccess', SRC)
        self.assertGreaterEqual(SRC.count('cudaMalloc(&gpu, bytes)'), 2)

    def test_safe_partial_state(self):
        self.assertNotIn('row_ = strata::kernels::iq_row_bytes(', SRC)
        self.assertRegex(SRC, r'staging.commit\(host_, dev_\);\s*bytes_ = bytes;')
        self.assertIn('if (!dev_) throw std::logic_error', SRC)

    def test_alias_owned_only_by_host(self):
        self.assertIn('if (device_owned_ && device_) release_device_(device_);', HDR)
        self.assertIn('if (host_) release_host_(host_);', HDR)
        self.assertIn('if (!device_owned_) device_ = nullptr;', HDR)

    def test_no_accidental_device_ownership_on_alias(self):
        self.assertIn('device_owned_ = false;', HDR)
        self.assertIn('device_owned_ = true;', HDR)


if __name__ == '__main__':
    unittest.main()
