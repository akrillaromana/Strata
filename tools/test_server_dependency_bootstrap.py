"""Regression for Windows .venv created without pip and missing jinja2.

These tests use a fake subprocess, and never install packages or alter an
interpreter.  The runtime bootstrap always operates on the selected Python.
"""
from __future__ import annotations

import contextlib
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from tools import ensure_server_dependencies as bootstrap


class ServerDependencyBootstrapTests(unittest.TestCase):
    def test_pipless_python_uses_ensurepip_then_requirements_and_reprobes(self):
        py = r"E:\ai\Strata-Q4-Fork\.venv\Scripts\python.exe"
        commands: list[list[str]] = []

        def run(command, **kwargs):
            command = list(command)
            commands.append(command)
            self.assertEqual(command[0], py)
            if command[1:3] == ["-c", bootstrap.IMPORT_PROBE]:
                if len([c for c in commands if c[1] == "-c"]) == 1:
                    return subprocess.CompletedProcess(command, 1, "", "ModuleNotFoundError: No module named 'jinja2'")
                return subprocess.CompletedProcess(command, 0, "STRATA_SERVER_DEPS_OK\n", "")
            if command[1:4] == ["-m", "pip", "--version"]:
                return subprocess.CompletedProcess(command, 1, "", "No module named pip")
            return subprocess.CompletedProcess(command, 0, "", "")

        with patch.object(bootstrap.subprocess, "run", side_effect=run):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertTrue(bootstrap.ensure_server_dependencies(interpreter=py))

        self.assertEqual([c[1:4] for c in commands], [
            ["-c", bootstrap.IMPORT_PROBE],
            ["-m", "pip", "--version"],
            ["-m", "ensurepip", "--upgrade"],
            ["-m", "pip", "install"],
            ["-c", bootstrap.IMPORT_PROBE],
        ])
        self.assertIn("repaired and verified", output.getvalue())
        self.assertEqual(commands[3][-2], "-r")
        self.assertEqual(Path(commands[3][-1]), bootstrap.REQUIREMENTS)

    def test_installed_dependencies_never_run_pip(self):
        cmd = ["python", "-c", bootstrap.IMPORT_PROBE]
        response = subprocess.CompletedProcess(cmd, 0, "STRATA_SERVER_DEPS_OK", "")
        with patch.object(bootstrap.subprocess, "run", return_value=response) as run:
            self.assertTrue(bootstrap.ensure_server_dependencies(interpreter="python"))
            run.assert_called_once()

    def test_check_only_does_not_modify_environment(self):
        failed = subprocess.CompletedProcess(["python"], 1, "", "No module named 'jinja2'")
        with patch.object(bootstrap.subprocess, "run", return_value=failed) as run:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertFalse(bootstrap.ensure_server_dependencies(interpreter="python", install_if_missing=False))
            run.assert_called_once()

    def test_server_has_early_guard_before_third_party_import(self):
        server = (bootstrap.ROOT / "serve/server.py").read_text(encoding="utf-8")
        self.assertLess(server.index('from tools.ensure_server_dependencies import ensure_server_dependencies'),
                        server.index('from serve.frontend import'))
        self.assertIn('ensure_server_dependencies(interpreter=sys.executable, install_if_missing=True)', server)

    def test_all_maintained_launchers_call_probe_before_ram_staging(self):
        rels = [
            "PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q4-RAM.ps1",
            "PERSONAL_START_E_ai_Strata-Q4-Fork/START-HUIHUI-Q4-RAM.ps1",
            "PERSONAL_START_E_ai_Strata-Q4-Fork/START-IQ3S-RAM.ps1",
            "PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q6-RAM.ps1",
            "PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q8-RAM.ps1",
            "START-PERSONAL-MODEL.ps1",
        ]
        for rel in rels:
            with self.subTest(rel=rel):
                txt = (bootstrap.ROOT / rel).read_text(encoding="utf-8")
                self.assertIn("Ensure-StrataServerPythonDependencies", txt)
                self.assertTrue("Resolve-StrataModelPython" in txt or "Resolve-StrataPython" in txt, rel)

if __name__ == "__main__":
    unittest.main()
