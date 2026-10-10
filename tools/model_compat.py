"""Offline GGUF shard/quantization audit for the Strata v0.1.39 custom fork.

Reads headers only. No model weights, GPU, setup or network access are needed.
It reports *candidate code paths*, never claims that a model was run or tested.

    python tools/model_compat.py X:/models/model-00001-of-00004.gguf
    python tools/model_compat.py X:/models/model.gguf --json

Designed by comparing the donor tools/strata_inspect.py/quantscope.py with
our own GGUF reader and the native MMVQ + PLE dispatch tables. Unlike the
upstream inspector, does not confuse a known tensor type with a known model.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gguf_reader as G

# Source: src/kernels/cuda/native_mmvq.cu native_mmvq_supported(), audited in 009.
NATIVE_MMVQ = frozenset({
    "Q4_0", "Q5_0", "Q5_1", "Q8_0", "Q3_K", "Q4_K", "Q5_K", "Q6_K", "IQ4_NL", "IQ4_XS",
    "Q2_0", "IQ2_XXS", "IQ2_XS", "IQ3_XXS", "IQ3_S", "IQ2_S", "IQ1_M",
})
PLE_TABLE = frozenset({"IQ4_NL", "Q5_0", "Q8_0", "I8"})
PLE_KEY = frozenset({"Q2_0", "Q8_0", "IQ3_XXS", "IQ4_XS"})
SHARD_RE = re.compile(r"^(?P<stem>.+)-(?P<n>\d{5})-of-(?P<total>\d{5})\.gguf$", re.I)


def discover(first: Path) -> list[Path]:
    """Return a complete ordered split, never a partial shard subset."""
    if not first.is_file() or first.suffix.lower() != ".gguf":
        raise ValueError(f"not a GGUF file: {first}")
    match = SHARD_RE.fullmatch(first.name)
    if match is None:
        return [first]
    total = int(match["total"])
    if total < 1 or total > 99999:
        raise ValueError("invalid shard count")
    if int(match["n"]) < 1 or int(match["n"]) > total:
        raise ValueError("invalid shard number")
    paths = [first.with_name(f"{match['stem']}-{i:05d}-of-{total:05d}.gguf")
             for i in range(1, total + 1)]
    missing = [str(p) for p in paths if not p.is_file()]
    if missing:
        raise ValueError(f"missing GGUF shards: {', '.join(missing[:4])}")
    return paths


def category(name: str) -> str:
    if name == "per_layer_token_embd.weight":
        return "ple_table"
    if name == "blk.1.ple_key.weight":
        return "ple_key"
    if ".ffn_" in name and "_exps.weight" in name:
        return "routed_experts"
    if ".ffn_" in name and "_shexp.weight" in name:
        return "shared_experts"
    if "attn" in name or "indexer" in name:
        return "attention"
    return "other"


def inspect(paths: list[Path]) -> dict:
    seen_names: set[str] = set()
    types: dict[str, Counter] = {}
    warnings: list[str] = []
    architecture: str | None = None
    declared_split_count: int | None = None
    split_numbers: set[int] = set()
    split_tensor_total: int | None = None
    split_tensor_seen = 0
    split_tensor_fields: list[int | None] = []
    tensor_count = 0
    ple_table_type: str | None = None
    ple_key_type: str | None = None
    ple_table_metadata_valid = True
    for index, path in enumerate(paths):
        gguf = G.GGUFFile(path)
        arch = gguf.metadata.get("general.architecture")
        if index == 0:
            architecture = arch
        elif arch is not None and arch != architecture:
            raise ValueError(f"shard {path.name} has conflicting general.architecture: {arch!r}")
        count = gguf.metadata.get("split.count")
        number = gguf.metadata.get("split.no")
        if count is not None or number is not None:
            if not isinstance(count, int) or count != len(paths):
                raise ValueError(f"shard {path.name} has wrong split.count: {count!r}")
            if not isinstance(number, int) or number < 0 or number >= len(paths):
                raise ValueError(f"shard {path.name} has invalid split.no: {number!r}")
            if number in split_numbers:
                raise ValueError(f"duplicate split.no: {number}")
            split_numbers.add(number)
            declared_split_count = count
        elif len(paths) > 1:
            warnings.append(f"{path.name} has no split metadata; name-based discovery only")
        declared_tensors = gguf.metadata.get("split.tensors.count")
        if len(paths) > 1:
            if declared_tensors is not None:
                if type(declared_tensors) is not int or declared_tensors < 1:
                    raise ValueError(f"{path.name}: invalid split.tensors.count")
                if split_tensor_total is not None and split_tensor_total != declared_tensors:
                    raise ValueError(f"{path.name}: conflicting split.tensors.count")
                split_tensor_total = declared_tensors
            # The engine's GgufModel requires shard 1 architecture and consistent
            # per-shard metadata. We deliberately mirror its fail-closed behaviour.
            if count is None or number != index:
                raise ValueError(f"{path.name}: missing/out-of-order split metadata")
        elif count is not None and count > 1:
            raise ValueError(f"{path.name}: model reports a split but only one file supplied")
        split_tensor_fields.append(declared_tensors)
        split_tensor_seen += len(gguf.tensors)
        file_bytes = path.stat().st_size
        if gguf.data_start > file_bytes:
            raise ValueError(f"{path.name}: GGUF data offset outside file")
        data_bytes = file_bytes - gguf.data_start
        for tensor in gguf.tensors:
            if tensor.name in seen_names:
                raise ValueError(f"duplicate tensor in split: {tensor.name}")
            seen_names.add(tensor.name)
            tensor_count += 1
            group = category(tensor.name)
            types.setdefault(group, Counter())[tensor.type_name] += 1
            size = tensor.expected_bytes()
            if size is None:
                warnings.append(f"{tensor.name}: unknown/unaligned tensor geometry for {tensor.type_name}")
            elif tensor.offset > data_bytes or size > data_bytes - tensor.offset:
                raise ValueError(f"{path.name}: truncated tensor {tensor.name}")
            if group == "ple_key":
                ple_key_type = tensor.type_name
            elif group == "ple_table":
                ple_table_type = tensor.type_name
                if len(tensor.shape) != 2 or tensor.shape[0] != 160 or (tensor.type_name == "Q8_0" and tensor.shape[1] != 320001536):
                    warnings.append("PLE table has unexpected geometry (Q8_0 requires [160, 320001536])")
                    ple_table_metadata_valid = False
                if tensor.type_name == "I8":
                    if (gguf.metadata.get("strata.ple.format") != "f8_e4m3" or
                            not isinstance(gguf.metadata.get("strata.ple.scale"), (int, float)) or
                            gguf.metadata["strata.ple.scale"] <= 0):
                        warnings.append("I8 PLE table is missing the required FP8 format/positive scale metadata")
                        ple_table_metadata_valid = False
    if split_tensor_total is not None:
        if split_tensor_seen != split_tensor_total:
            raise ValueError(f"split.tensors.count={split_tensor_total} but {split_tensor_seen} tensor entries found")
        # One shard specifying a total while the others do not is unsafe: the
        # actual C++ split reader rejects the inconsistent directories as well.
        if any(field != split_tensor_total for field in split_tensor_fields):
            raise ValueError("split.tensors.count missing on one or more shards")
    if declared_split_count is not None and len(split_numbers) != declared_split_count:
        warnings.append("not all shards carried split metadata")
    if architecture != "qwen4exp":
        warnings.append(f"model architecture {architecture!r} is not the verified qwen4exp target")
    expert_types = set(types.get("routed_experts", {}))
    if "Q6_K" in expert_types:
        warnings.append("Q6_K routed experts require opt-in STRATA_Q6K_EXPERTS and STRATA_MMQ_KQUANTS; GPU path unverified")
    if "Q8_0" in expert_types or ple_table_type == "Q8_0":
        warnings.append("Q8_0 code paths exist, but complete native model/Huihui compatibility is unverified")
    other_experts = expert_types - NATIVE_MMVQ
    if other_experts:
        warnings.append(f"expert formats without known native MMVQ path: {', '.join(sorted(other_experts))}")
    if ple_key_type is not None and ple_key_type not in PLE_KEY and ple_key_type not in {"BF16", "F16", "F32"}:
        warnings.append(f"PLE key {ple_key_type} requires pack conversion; not native")
    if ple_table_type is not None and ple_table_type not in PLE_TABLE:
        warnings.append(f"PLE table {ple_table_type} not supported by the existing n-gram reader")
    return {
        "architecture": architecture,
        "files": [p.name for p in paths],
        "tensor_count": tensor_count,
        "quantization_by_role": {k: dict(sorted(v.items())) for k, v in sorted(types.items())},
        "ple_table": {"type": ple_table_type,
                      "native_reader_type": ple_table_type in PLE_TABLE and ple_table_metadata_valid},
        "ple_key": {"type": ple_key_type, "native_mmvq_type": ple_key_type in PLE_KEY},
        "experimental": bool(warnings),
        "warnings": warnings,
        "full_model_compatibility_verified": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("gguf", type=Path, help="one local GGUF file, including any shard of a complete split")
    parser.add_argument("--json", action="store_true", help="machine-readable audit result")
    args = parser.parse_args(argv)
    try:
        result = inspect(discover(args.gguf))
    except (OSError, ValueError, KeyError, EOFError, IndexError) as exc:
        parser.exit(2, f"GGUF audit rejected: {exc}\n")
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"Architecture: {result['architecture']}  tensors: {result['tensor_count']}")
        print(f"Shards: {len(result['files'])}")
        for group, kinds in result["quantization_by_role"].items():
            print(f"  {group}: {', '.join(f'{q}={n}' for q, n in kinds.items())}")
        for warning in result["warnings"]:
            print(f"WARNING: {warning}")
        print("Full model compatibility: NOT VERIFIED (header-only audit)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
