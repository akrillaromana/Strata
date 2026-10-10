"""Offline Qwen3.8 Flash Next Q8_0 n-gram/PLE table verification.

Reads GGUF *headers* from the original model shards. It does not read weights,
run the engine, require CUDA, change configurations, or download anything.

Usage: python tools/q8_ple_preflight.py R:/q8-model/model-00001-of-00006.gguf
The native Q8 launch JSON relies on the same GGUF model-shard auto-discovery.
A missing IQ4_NL-free Q8_0 table is an ERROR, not a fallback.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from model_compat import discover
from gguf_reader import GGUFFile

PLE_ROWS = 320001536
PLE_DIM = 160
Q8_ROW_BYTES = 170
TENSOR = "per_layer_token_embd.weight"


def locate(model: Path) -> dict:
    paths = discover(model)
    found = []
    for path in paths:
        gg = GGUFFile(path)
        for t in gg.tensors:
            if t.name != TENSOR:
                continue
            if t.type_name != "Q8_0":
                raise ValueError(f"Q8_0 n-gram required; {path} has {t.type_name}, refusing IQ4_NL fallback")
            if t.shape != [PLE_DIM, PLE_ROWS]:
                raise ValueError(f"unexpected Q8_0 n-gram geometry in {path}: {t.shape!r}")
            size = PLE_ROWS * Q8_ROW_BYTES
            file_size = path.stat().st_size
            start = gg.data_start + t.offset
            if gg.data_start > file_size or start > file_size or size > file_size - start:
                raise ValueError(f"truncated Q8_0 n-gram tensor in {path}")
            found.append(path)
    if len(found) != 1:
        raise ValueError(f"expected one native Q8_0 n-gram tensor across model shards; found {len(found)}")
    return {"quantization": "Q8_0", "source": str(found[0]), "rows": PLE_ROWS,
            "row_bytes": Q8_ROW_BYTES, "table_bytes": PLE_ROWS * Q8_ROW_BYTES,
            "shards": len(paths), "verified": "GGUF headers and tensor boundaries only"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gguf", type=Path, help="any shard of the original, complete Q8_0 model")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = locate(args.gguf)
    except (OSError, ValueError, EOFError, IndexError, KeyError) as exc:
        print(f"NATIVE Q8_0 PLE UNAVAILABLE: {exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"Q8_0 n-gram confirmed in GGUF headers: {result['source']}")
        print(f"Rows: {result['rows']}, bytes/row: {result['row_bytes']}; shards: {result['shards']}")
        print("Inference/runtime compatibility is NOT verified (header-only check).")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
