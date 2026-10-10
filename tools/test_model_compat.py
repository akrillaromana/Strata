"""Synthetic GGUF fixtures: header-only quantization and shard audit."""
from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import model_compat as audit


def string(value: str) -> bytes:
    raw = value.encode("utf-8")
    return struct.pack("<Q", len(raw)) + raw


def metadata(key: str, value) -> bytes:
    if isinstance(value, str):
        return string(key) + struct.pack("<I", 8) + string(value)
    return string(key) + struct.pack("<IH", 2, value)


def gguf(path: Path, tensors: list[tuple[str, tuple[int, ...], int]], *, split=None,
         architecture="qwen4exp", short=False) -> None:
    kv = [("general.architecture", architecture)] if architecture else []
    if split is not None:
        kv += [("split.no", split[0]), ("split.count", split[1])]
    header = bytearray(b"GGUF" + struct.pack("<IQQ", 3, len(tensors), len(kv)))
    for k, v in kv:
        header += metadata(k, v)
    offset = 0
    data = bytearray()
    for name, shape, kind in tensors:
        header += string(name)
        header += struct.pack("<I", len(shape))
        header += struct.pack("<" + "Q" * len(shape), *shape)
        header += struct.pack("<IQ", kind, offset)
        n = 1
        for d in shape:
            n *= d
        block, stride = {8: (32, 34), 14: (256, 210), 30: (1, 2)}[kind]
        if n % block:
            raise ValueError("bad fixture")
        buf = bytes(n // block * stride)
        offset += len(buf)
        data += buf
    header += bytes(-len(header) % 32)
    path.write_bytes(header + (data[:-1] if short else data))


class OfflineAuditTests(unittest.TestCase):
    def test_complete_q8_ple_and_q6_experts_reported_as_experimental(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = root / "Huihui-Q8-00001-of-00002.gguf"
            b = root / "Huihui-Q8-00002-of-00002.gguf"
            gguf(a, [("per_layer_token_embd.weight", (160, 1), 8)], split=(0, 2))
            gguf(b, [("blk.1.ffn_gate_exps.weight", (256, 1), 14)], split=(1, 2), architecture=None)
            result = audit.inspect(audit.discover(b))
            self.assertEqual(result["ple_table"]["type"], "Q8_0")
            self.assertFalse(result["ple_table"]["native_reader_type"])
            self.assertFalse(result["full_model_compatibility_verified"])
            self.assertEqual(result["quantization_by_role"]["routed_experts"], {"Q6_K": 1})
            self.assertIn("Q6_K", " ".join(result["warnings"]))

    def test_split_total_mismatch_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = root / "q6-00001-of-00002.gguf"
            b = root / "q6-00002-of-00002.gguf"
            gguf(a, [("blk.1.ple_key.weight", (32, 1), 8)], split=(0, 2))
            gguf(b, [("blk.1.ffn_gate_exps.weight", (256, 1), 14)], split=(1, 2), architecture=None)
            from unittest.mock import patch
            original = audit.G.GGUFFile
            class GgufWithMeta(original):
                def __init__(self, path):
                    super().__init__(path)
                    self.metadata["split.tensors.count"] = 2 if Path(path) == a else 3
            with patch.object(audit.G, "GGUFFile", GgufWithMeta):
                with self.assertRaisesRegex(ValueError, "conflicting split.tensors.count"):
                    audit.inspect([a, b])

    def test_split_missing_metadata_refused_as_engine_would(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = root / "q6-00001-of-00002.gguf"
            b = root / "q6-00002-of-00002.gguf"
            gguf(a, [("blk.1.ple_key.weight", (32, 1), 8)], split=(0, 2))
            gguf(b, [("blk.1.ffn_gate_exps.weight", (256, 1), 14)], architecture=None)
            with self.assertRaisesRegex(ValueError, "missing/out-of-order split metadata"):
                audit.inspect([a, b])

    def test_missing_shard_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = root / "test-00001-of-00002.gguf"
            gguf(a, [("blk.1.ple_key.weight", (32, 1), 8)], split=(0, 2))
            with self.assertRaisesRegex(ValueError, "missing GGUF shards"):
                audit.discover(a)

    def test_duplicate_tensor_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = root / "x-00001-of-00002.gguf"
            b = root / "x-00002-of-00002.gguf"
            tensor = [("blk.1.ple_key.weight", (32, 1), 8)]
            gguf(a, tensor, split=(0, 2))
            gguf(b, tensor, split=(1, 2), architecture=None)
            with self.assertRaisesRegex(ValueError, "duplicate tensor"):
                audit.inspect(audit.discover(a))

    def test_conflicting_architecture_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = root / "x-00001-of-00002.gguf"
            b = root / "x-00002-of-00002.gguf"
            gguf(a, [("blk.1.ple_key.weight", (32, 1), 8)], split=(0, 2))
            gguf(b, [("blk.2.attn_q.weight", (32, 1), 8)], split=(1, 2), architecture="other")
            with self.assertRaisesRegex(ValueError, "conflicting"):
                audit.inspect(audit.discover(a))

    def test_corrupt_tensor_data_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp) / "model.gguf"
            gguf(p, [("per_layer_token_embd.weight", (160, 1), 8)], short=True)
            with self.assertRaisesRegex(ValueError, "truncated tensor"):
                audit.inspect([p])

    def test_fp8_ple_without_required_metadata_is_not_claimed_supported(self):
        with tempfile.TemporaryDirectory() as temp:
            # GGUF I8 (24) isn't present in the fixture writer's block table;
            # this deliberately tests the metadata gate with a fake reader.
            class T:
                name = "per_layer_token_embd.weight"
                type_name = "I8"
                shape = [160, 1]
                offset = 0
                def expected_bytes(self): return 160

            class File:
                metadata = {"general.architecture": "qwen4exp"}
                data_start = 32
                tensors = [T()]

            from unittest.mock import patch
            p = Path(temp) / "model.gguf"
            p.write_bytes(bytes(192))
            with patch.object(audit.G, "GGUFFile", return_value=File()):
                result = audit.inspect([p])
            self.assertFalse(result["ple_table"]["native_reader_type"])
            self.assertIn("missing the required FP8", " ".join(result["warnings"]))

    def test_valid_ple_key_classification_and_json(self):
        with tempfile.TemporaryDirectory() as temp:
            p = Path(temp) / "model.gguf"
            gguf(p, [("blk.1.ple_key.weight", (256, 1), 14),
                     ("blk.2.hc_attn_down.weight", (32, 1), 8)])
            result = audit.inspect([p])
            self.assertFalse(result["ple_key"]["native_mmvq_type"])
            self.assertIn("requires pack conversion", " ".join(result["warnings"]))
            self.assertFalse(json.loads(json.dumps(result))["full_model_compatibility_verified"])

    def test_split_metadata_number_repeated(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            a = root / "x-00001-of-00002.gguf"
            b = root / "x-00002-of-00002.gguf"
            gguf(a, [("blk.1.ple_key.weight", (32, 1), 8)], split=(0, 2))
            gguf(b, [("blk.2.attn_q.weight", (32, 1), 8)], split=(0, 2), architecture=None)
            with self.assertRaisesRegex(ValueError, "duplicate split.no"):
                audit.inspect(audit.discover(a))


if __name__ == "__main__":
    unittest.main()
