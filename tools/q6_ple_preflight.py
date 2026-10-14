"""Offline preflight for the user's Qwen3.8 Flash Next Q6_K split.

Reads GGUF headers only. The supported inventory is exactly five shards named
Qwen3.8-Flash-Next-Q6_K-00001-of-00005.gguf ... 00005-of-00005.gguf.
It requires routed Q6_K experts and one native Q8_0 PLE table. Tensor payloads
are not hashed and are not read into memory.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from gguf_reader import GGUFFile
from model_compat import discover, inspect

PLE = "per_layer_token_embd.weight"
EXPECTED = [f"Qwen3.8-Flash-Next-Q6_K-{i:05d}-of-00005.gguf" for i in range(1, 6)]


def locate(first: Path) -> dict:
    paths = discover(first)
    names = [p.name for p in paths]
    if names != EXPECTED:
        raise ValueError(f"expected the five Q6_K shards {EXPECTED}; got {names}")
    audit = inspect(paths)
    routed = audit.get("quantization_by_role", {}).get("routed_experts", {})
    if not routed or "Q6_K" not in routed:
        raise ValueError(f"routed Q6_K experts were not found; got {sorted(routed)}")
    found: list[tuple[Path, str, list[int]]] = []
    for path in paths:
        gg = GGUFFile(path)
        for tensor in gg.tensors:
            if tensor.name == PLE:
                found.append((path, tensor.type_name, list(tensor.shape)))
    if len(found) != 1:
        raise ValueError(f"expected exactly one {PLE}; found {len(found)}")
    ple_path, ple_type, ple_shape = found[0]
    if ple_type != "Q8_0":
        raise ValueError(f"Q6_K PLE must be Q8_0 to match the Q8_0 runtime contract; got {ple_type}")
    if not audit.get("ple_table", {}).get("native_reader_type"):
        raise ValueError("PLE metadata/geometry failed native reader validation")
    files = [{"name": p.name, "bytes": p.stat().st_size} for p in paths]
    return {
        "architecture": audit.get("architecture"),
        "shards": 5,
        "files": files,
        "routed_experts": routed,
        "ple_type": ple_type,
        "ple_shape": ple_shape,
        "ple_source": str(ple_path),
        "ple_source_name": ple_path.name,
        "ple_source_bytes": ple_path.stat().st_size,
        "verified": "GGUF headers, exact five-shard Q6_K inventory, payload boundaries, Q6_K routed experts and native Q8_0 PLE metadata; tensor values were not read",
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("gguf", type=Path, help="any shard of the complete five-file Q6_K split")
    ap.add_argument("--json", action="store_true")
    ns = ap.parse_args(argv)
    try:
        result = locate(ns.gguf)
    except (OSError, ValueError, EOFError, IndexError, KeyError) as exc:
        print(f"Q6_K PREFLIGHT FAILED: {exc}", file=sys.stderr)
        return 2
    if ns.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"Q6_K split: 5 shards; PLE Q8_0 in {result['ple_source_name']}")
        print("Inference/runtime compatibility is NOT proven by this header-only check.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
