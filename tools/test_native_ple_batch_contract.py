"""Source-only checks for CUDA/HIP and SYCL PLE prompt-batch preflight."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATHS = (
    'src/kernels/cuda/native_ple_postops.cu',
    'sycl/src/kernels/cuda/native_ple_postops.dp.cpp',
)


class PleBatchContract(unittest.TestCase):
    def test_all_backends_preflight_dimensions(self):
        for path in PATHS:
            with self.subTest(path=path):
                text = (ROOT / path).read_text()
                batch = text.split('void native_ple_postops_batch(', 1)[1]
                self.assertIn('#include "strata/kernels/native_ple_batch_shape.hpp"', text)
                self.assertIn('native_ple_batch_shape(T)', batch)
                self.assertIn('const unsigned rows = geometry.rows;', batch)
                self.assertIn('const unsigned blocks = geometry.blocks;', batch)
                self.assertNotIn('unsigned(T) * H', batch)
                self.assertNotIn('(size_t(T) * D + 255)', batch)

    def test_no_backend_allows_aliasing_or_unvalidated_weights(self):
        for path in PATHS:
            with self.subTest(path=path):
                batch = (ROOT / path).read_text().split('void native_ple_postops_batch(', 1)[1]
                self.assertIn('native_ple_batch_nonoverlap(data', batch)
                self.assertIn('native_ple_batch_nonoverlap(pair, 2)', batch)
                self.assertIn('w.conv1d_f16', batch)
                self.assertIn('w.norm_key', batch)
                self.assertIn('w.norm_query', batch)
                self.assertIn('w.norm_conv', batch)

    def test_shape_test_registered_in_cmake(self):
        cmake = (ROOT / 'CMakeLists.txt').read_text()
        self.assertIn('tests/cpu/native_ple_batch_shape_test.cpp', cmake)
        self.assertIn('add_test(NAME native_ple_batch_shape_test', cmake)


if __name__ == '__main__':
    unittest.main()
