"""Проверки адресной калибровки Strata без CUDA, GPU и настоящих моделей."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from serve.server import model_autotune_args


class ModelCalibrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "model-autotune").mkdir()
        self.exe = self.root / "strata.exe"
        self.exe.write_bytes(b"engine-build-a")
        self.args = ["--native", "R:\\different-model\\shard-1.gguf",
                     "--pcie-frac", "0.26", "--spec-min-p", "0.75", "--mtp", "R:\\draft"]
        self.cfg = {"cwd": str(self.root), "exe": str(self.exe), "model_name": "variant-A"}
        self.key = hashlib.sha256(("variant-A\n" + self.args[1]).encode()).hexdigest()
        self.path = self.root / "model-autotune" / (self.key + ".json")

    def save(self, **overrides):
        profile = {
            "version": 1,
            "model_name": "variant-A",
            "native": self.args[1],
            "profile_key": self.key,
            "engine_sha256": hashlib.sha256(self.exe.read_bytes()).hexdigest(),
            "settings": {"pcie_frac": 0.35, "spec_min_p": 0.7},
        }
        profile.update(overrides)
        self.path.write_text(json.dumps(profile), encoding="utf-8")

    def test_applies_only_matching_profile(self):
        self.save()
        tuned = model_autotune_args(self.cfg, self.args)
        self.assertEqual(tuned[tuned.index("--pcie-frac") + 1], "0.3500")
        self.assertEqual(tuned[tuned.index("--spec-min-p") + 1], "0.7000")
        self.assertEqual(self.args[self.args.index("--pcie-frac") + 1], "0.26")

    def test_other_model_and_other_shard_are_unchanged(self):
        self.save()
        self.assertEqual(model_autotune_args({**self.cfg, "model_name": "variant-B"}, self.args), self.args)
        other_args = ["--native", "R:\\different-model\\another.gguf", "--pcie-frac", "0.55"]
        self.assertEqual(model_autotune_args(self.cfg, other_args), other_args)

    def test_other_exe_and_opt_out_are_unchanged(self):
        self.save()
        self.exe.write_bytes(b"engine-build-b")
        self.assertEqual(model_autotune_args(self.cfg, self.args), self.args)
        self.exe.write_bytes(b"engine-build-a")
        self.assertEqual(model_autotune_args({**self.cfg, "autotune": False}, self.args), self.args)

    def test_corrupt_or_out_of_range_is_never_applied(self):
        self.save(settings={"pcie_frac": 1.9})
        self.assertEqual(model_autotune_args(self.cfg, self.args), self.args)
        self.path.write_text("not json", encoding="utf-8")
        self.assertEqual(model_autotune_args(self.cfg, self.args), self.args)

    def test_unsupported_key_is_rejected(self):
        self.save(settings={"pool_workers": 3, "pcie_frac": 0.2})
        self.assertEqual(model_autotune_args(self.cfg, self.args), self.args)

    def test_can_add_flag_to_profile_without_one(self):
        self.save(settings={"pcie_frac": 0.2})
        args = ["--native", self.args[1]]
        self.assertEqual(model_autotune_args(self.cfg, args), args + ["--pcie-frac", "0.2000"])


if __name__ == "__main__":
    unittest.main()
