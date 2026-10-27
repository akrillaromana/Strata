"""Проверка личного каталога: без доступа к E:, без изменений файлов моделей."""
from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


class ModelCatalogContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / "configs" / "MODEL-CATALOG.json").read_text(encoding="utf-8"))

    def test_defaults_match_product(self):
        d = self.catalog["defaults"]
        self.assertEqual((d["pcie_frac"], d["spec_min_p"], d["parallel"]), (0.09, 0.9, 1))
        self.assertEqual((d["spec"], d["reasoning_budget_tokens"]), (4, 10240))
        self.assertEqual((d["max_context"], d["kv"], d["kv_resident"]), (262144, "int8", 32768))

    def test_ids_are_unique_and_safe(self):
        entries = self.catalog["models"]
        self.assertEqual(len({x["id"] for x in entries}), len(entries))
        self.assertEqual(len(entries), 16)
        for entry in entries:
            self.assertRegex(entry["id"], r"^[a-z0-9][a-z0-9-]*$")
            self.assertTrue(entry["first_shard"].startswith("E:\\ai\\models\\"))
            self.assertTrue(entry["first_shard"].lower().endswith(".gguf"))

    def test_flash_next_and_unsupported_are_separated(self):
        ready = [x for x in self.catalog["models"] if x["architecture"] == "qwen4exp"]
        pending = [x for x in self.catalog["models"] if x["architecture"] != "qwen4exp"]
        self.assertEqual((len(ready), len(pending)), (11, 5))
        for entry in ready:
            self.assertTrue(entry["pack"].startswith("E:\\ai\\Strata-data\\packs\\catalog\\"))
            self.assertNotIn("status", entry)
        for entry in pending:
            self.assertEqual(entry["architecture"], "qwen35moe")
            self.assertIn("движка", entry["status"])
            self.assertNotIn("pack", entry)

    def test_launcher_refuses_unsupported_and_preserves_source(self):
        source = (ROOT / "START-CATALOG-MODEL.ps1").read_text(encoding="utf-8")
        self.assertIn("$Model.architecture -ne 'qwen4exp'", source)
        self.assertIn("Get-Content -LiteralPath $CatalogPath -Raw", source)
        self.assertIn("'runtime-'", source)
        self.assertIn("$PreviousStages", source)
        self.assertNotIn("Remove-Item -LiteralPath $Pack", source)
        self.assertIn("Ensure-StrataServerPythonDependencies", source)
        self.assertIn("--pcie-frac", source)
        self.assertIn("--spec-min-p", source)
        self.assertIn("--mtp", source)


if __name__ == "__main__":
    unittest.main()
