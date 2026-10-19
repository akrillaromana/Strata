"""Iteration 059 product-default and Windows launcher bootstrap invariants."""
from __future__ import annotations

import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG_DIRS = (
    ROOT,
    ROOT / "PERSONAL_START_E_ai_Strata-Q4-Fork",
    ROOT / "tools/windows/q4-local-profiles",
    ROOT / "tools/windows/native-high-quant",
)


class Iteration059Defaults(unittest.TestCase):
    def test_all_active_mtp_jsons_use_new_defaults(self):
        seen = []
        for directory in CONFIG_DIRS:
            for path in sorted(directory.glob("*.json")):
                try:
                    cfg = json.loads(path.read_text(encoding="utf-8-sig"))
                except (json.JSONDecodeError, UnicodeDecodeError):
                    continue
                args = cfg.get("args")
                if not isinstance(args, list) or "--mtp" not in args:
                    continue
                seen.append(path.relative_to(ROOT).as_posix())
                with self.subTest(path=path.relative_to(ROOT).as_posix()):
                    self.assertEqual(args[args.index("--pcie-frac") + 1], "0.09")
                    self.assertEqual(args[args.index("--spec-min-p") + 1], "0.9")
                    self.assertEqual(cfg.get("parallel"), 2)
        self.assertEqual(len(seen), 25, seen)

    def test_launcher_defaults_and_dependency_probe(self):
        launchers = [
            ROOT / "START-IQ3S-RAM.ps1",
            ROOT / "START-Q6-RAM.ps1",
            ROOT / "PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q4-RAM.ps1",
            ROOT / "PERSONAL_START_E_ai_Strata-Q4-Fork/START-HUIHUI-Q4-RAM.ps1",
            ROOT / "PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q6-RAM.ps1",
            ROOT / "PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q8-RAM.ps1",
            ROOT / "tools/windows/q4-local-profiles/START-Q4-RAM.ps1",
            ROOT / "tools/windows/q4-local-profiles/START-HUIHUI-Q4-RAM.ps1",
            ROOT / "tools/windows/q4-local-profiles/START-Q6-RAM.ps1",
            ROOT / "tools/windows/q4-local-profiles/START-Q8-RAM.ps1",
        ]
        for path in launchers:
            text = path.read_text(encoding="utf-8-sig")
            with self.subTest(path=path.relative_to(ROOT).as_posix()):
                self.assertIn("Ensure-StrataServerPythonDependencies", text)
                self.assertRegex(text, r"parallel\s*=\s*2")
                self.assertNotRegex(text, r"--pcie-frac['\",\s]+0\.26")

    def test_common_bootstrap_repairs_stale_venv(self):
        text = (ROOT / "STRATA-MODEL-LAUNCH-COMMON.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("function Ensure-StrataServerPythonDependencies", text)
        self.assertIn("tools\\ensure_server_dependencies.py", text)
        helper = (ROOT / "tools/ensure_server_dependencies.py").read_text(encoding="utf-8")
        self.assertIn("import jinja2, regex, yaml, requests, PIL, psutil, jsonschema, referencing", helper)
        self.assertIn("ensurepip", helper)
        self.assertIn("requirements.txt", helper)
        self.assertIn("engine-q6\\strata.exe", text)
        req = (ROOT / "requirements.txt").read_text(encoding="utf-8")
        self.assertRegex(req, r"(?m)^jinja2==")

    def test_setup_engine_and_calibration_defaults_match(self):
        setup = (ROOT / "setup.py").read_text(encoding="utf-8")
        self.assertIn('"--pcie-frac", "0.09"', setup)
        self.assertIn('cfg["parallel"] = 2', setup)
        cal = (ROOT / "tools/calibrate.py").read_text(encoding="utf-8")
        self.assertIn('DEFAULTS = {"--pcie-frac": "0.09", "--spec-min-p": "0.9"', cal)
        for rel in ("src/program/generate.cpp", "sycl/src/program/generate.cpp"):
            src = (ROOT / rel).read_text(encoding="utf-8")
            self.assertIn("double pcie_frac = 0.09;", src)


if __name__ == "__main__":
    unittest.main()
