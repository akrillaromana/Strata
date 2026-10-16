from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ExpertCudaParityContract(unittest.TestCase):
    def text(self, rel):
        return (ROOT / rel).read_text(encoding='utf-8')

    def test_cli_is_opt_in_and_q8_fail_closed(self):
        g = self.text('src/program/generate.cpp')
        self.assertIn('std::string expert_parity = "off"', g)
        self.assertIn('--expert-parity', g)
        n = self.text('src/kernels/cpu/native_expert.cpp')
        self.assertIn('supports only native Q8_0/Q8_0 experts', n)
        cfg = self.text('strata-unsloth-q8_0.json')
        self.assertNotIn('--expert-parity', cfg)

    def test_base_avx512_does_not_require_vnni_vbmi(self):
        e = self.text('src/kernels/cpu/expert_layout.cpp')
        m = re.search(r'bool cpu_avx512_base_ok\(\) \{(.*?)\n\}', e, re.S)
        self.assertIsNotNone(m)
        body = m.group(1)
        self.assertIn('ebx >> 16', body)  # F
        self.assertIn('ebx >> 17', body)  # DQ
        self.assertIn('ebx >> 30', body)  # BW
        self.assertIn('ebx >> 31', body)  # VL
        self.assertNotIn('ecx >> 11', body)  # VNNI
        self.assertNotIn('ecx >> 1', body)   # VBMI

    def test_q8_cpu_parity_uses_avx512_exact_integer_helper(self):
        q = self.text('src/kernels/cpu/q8_cuda_parity.cpp')
        a = self.text('src/kernels/cpu/q8_cuda_parity_avx512.cpp')
        self.assertIn('cpu_avx512_base_ok()', q)
        self.assertIn('q8_cuda_parity_dot4_avx512', q)
        self.assertIn('_mm512_cvtepi8_epi16', a)
        self.assertIn('_mm512_mullo_epi16', a)

    def test_host_device_swiglu_contract_shared(self):
        math = self.text('include/strata/kernels/expert_parity_math.hpp')
        cu = self.text('src/kernels/cuda/iq_kernels.cu')
        cpu = self.text('src/kernels/cpu/q8_cuda_parity.cpp')
        self.assertIn('parity_silu_mul', math)
        self.assertIn('swiglu_entries_parity_kernel', cu)
        self.assertIn('parity_silu_mul(gate[i], up[i])', cu)
        self.assertIn('parity_silu_mul(g, u)', cpu)

    def test_compiler_keeps_parity_arithmetic_strict(self):
        c = self.text('CMakeLists.txt')
        self.assertIn('q8_cuda_parity.cpp PROPERTIES COMPILE_OPTIONS "/fp:strict"', c)
        self.assertIn('q8_cuda_parity_avx512.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX512;/fp:strict"', c)
        self.assertIn('-ffp-contract=off;-fno-fast-math', c)

    def test_direct_cuda_cpu_gate_before_engine_install(self):
        build = self.text('BUILD_AND_START_IQ3S.ps1')
        copy_at = build.index("Copy-Item -LiteralPath $binary -Destination $engineTarget -Force")
        test_at = build.index('& $ParityExe --cuda-placement-parity-q8')
        self.assertLess(test_at, copy_at)
        self.assertIn("новый strata.exe НЕ устанавливается", build)
        native = self.text('src/kernels/native_expert_parity.cpp')
        self.assertIn('expert parity=cuda CPU vs GPU', native)
        self.assertIn('bit_diff != 0', native)

    def test_windows_launch_and_end_to_end_pcie_test(self):
        outer = self.text('START-Q8-RAM.ps1')
        inner = self.text('PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q8-RAM.ps1')
        self.assertIn('ExpertParityCuda', outer)
        self.assertIn("$ParityFlags['--expert-parity'] = 'cuda'", inner)
        p = self.text('TEST-PCIE-PARITY.ps1')
        for v in ('0.0', '0.2', '0.26', '0.5', '1.0'):
            self.assertIn(v, p)
        self.assertIn('temperature = 0', p)
        self.assertIn('PCIE PARITY FAIL', p)

    def test_user_json_remains_read_only(self):
        inner = self.text('PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q8-RAM.ps1')
        self.assertIn('New-StrataModelRuntimeConfig', inner)
        self.assertNotIn('Write-StrataModelConfiguration', inner)

if __name__ == '__main__':
    unittest.main()
