"""Static regression guards for iteration 056 live PCIe/MTP tuning and immutable source configs."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RuntimeTuneSourceTests(unittest.TestCase):
    def test_engine_has_real_live_scheduler_setter(self):
        src = (ROOT / "src/program/generate.cpp").read_text(encoding="utf-8")
        self.assertIn('request_tune=2 live_tune=1', src)
        self.assertIn('line == "TUNE" || line.rfind("TUNE ", 0) == 0', src)
        self.assertIn('live_pcie_frac = next_pcie', src)
        self.assertIn('drive.d.pcie_num = pcie_num_of(live_pcie_frac)', src)
        self.assertIn('std::printf("TUNED %.6f %.6f %d\\n"', src)
        self.assertIn('drive.d.pcie_num = std::max(0, std::min(256, (int) (req_pcie_frac * 256.0 + 0.5)))', src)
        self.assertIn('(long long) req_offload, req_pcie_frac, req_spec_min_p', src)

    def test_web_apply_calls_live_tune_before_success(self):
        js = (ROOT / "serve/web/app.js").read_text(encoding="utf-8")
        self.assertIn('fetch("runtime-tune"', js)
        self.assertIn('liveAck = await applyRuntimeTuneNow(newRuntimeTune)', js)
        self.assertIn('PCIe offload ${fmt(timings.pcie_offloaded_entries)} entries', js)
        self.assertNotIn('fetch("config", {method: "POST"', js)

    def test_runtime_server_refuses_config_write(self):
        server = (ROOT / "serve/server.py").read_text(encoding="utf-8")
        runconfig = (ROOT / "serve/runconfig.py").read_text(encoding="utf-8")
        self.assertIn('run config is read-only; Strata never overwrites model JSON files', server)
        self.assertIn('raise PermissionError(f"run config is read-only:', runconfig)
        self.assertIn('if cfg.get("autotune") is not True', server)


if __name__ == "__main__":
    unittest.main()
