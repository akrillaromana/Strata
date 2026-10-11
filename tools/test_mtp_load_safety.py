"""Source integration contract for MTP exception-safe CUDA resource and KV state handling."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class TestMtpLoadSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'src/core/mtp.cpp').read_text(encoding='utf-8')
        cls.kernel = (ROOT / 'src/kernels/cuda/mtp_native_experts.cu').read_text(encoding='utf-8')
        cls.header = (ROOT / 'include/strata/core/mtp_load_safety.hpp').read_text(encoding='utf-8')

    def test_global_kv_mode_guard_is_used(self):
        self.assertIn('MtpScopedKvMode draft_kv_mode(', self.source)
        self.assertIn('qsa_kv_int8(), qsa_kv_hybrid()', self.source)
        self.assertIn('qsa_set_kv_int8, qsa_set_kv_hybrid', self.source)
        self.assertIn('~MtpScopedKvMode()', self.header)

    def test_no_unguarded_restore_after_failure_returns(self):
        self.assertNotIn('qsa_set_kv_int8(kv_int8_was)', self.source)
        self.assertNotIn('qsa_set_kv_hybrid(kv_hybrid_was)', self.source)
        self.assertIn('set_int8_(previous_int8_);', self.header)
        self.assertIn('set_hybrid_(previous_hybrid_);', self.header)

    def test_gpu_arena_fallback_does_not_leave_dangling_pointer(self):
        self.assertIn('cudaFree(state_arena_);\n            state_arena_ = nullptr;', self.source)

    def test_mapped_alias_uses_transactional_helper(self):
        self.assertIn('mtp_mapped_allocation(bytes, h, d,', self.source)
        self.assertIn('cudaHostGetDevicePointer(device, host, 0)', self.source)
        self.assertIn('cudaFreeHost(host)', self.source)
        self.assertIn('release(candidate_host);', self.header)

    def test_native_kernel_rejects_incompatible_topk(self):
        self.assertIn('mtp_native_launch_shape(', self.kernel)
        header = (ROOT / 'include/strata/kernels/mtp_native_launch_shape.hpp').read_text(encoding='utf-8')
        self.assertIn('hits % k == 0', header)
        self.assertIn('ff <= (std::numeric_limits<int>::max() - 255) / hits', header)
        self.assertIn('ff <= std::numeric_limits<int>::max() / 2', header)

    def test_drafter_instance_rejects_double_load_and_cuda_device_failure(self):
        self.assertIn('if (dense_ || experts_ || state_arena_ || arena_ || cs_ || h_tok_ || h_cparams_)', self.source)
        self.assertIn('drafter already loaded or partially initialized', self.source)
        self.assertIn('if (cudaGetDevice(&device_) != cudaSuccess)', self.source)

    def test_cmake_and_native_test_exist(self):
        cmake = (ROOT / 'CMakeLists.txt').read_text(encoding='utf-8')
        self.assertIn('add_test(NAME mtp_load_safety_test COMMAND mtp_load_safety_test)', cmake)
        self.assertTrue((ROOT / 'tests/cpu/mtp_load_safety_test.cpp').is_file())


if __name__ == '__main__':
    unittest.main()
