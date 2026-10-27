"""tools/ple_shard.py - which shard of a split GGUF holds the PLE (n-gram) table.

    python tools/ple_shard.py --gguf <model>-00001-of-0000N.gguf

Prints the path of the shard that carries per_layer_token_embd.weight (the PLE table the
engine reads via --ple-gguf); exits 1 when no shard has it. Reads only the metadata.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gguf_reader as G  # noqa: E402

PLE_TENSOR = "per_layer_token_embd.weight"


def shards(first: pathlib.Path) -> list[pathlib.Path]:
    m = re.search(r"-(\d{5})-of-(\d{5})\.gguf$", first.name)
    if not m:
        return [first]
    total = int(m.group(2))
    return [first.with_name(first.name[:m.start()] + "-%05d-of-%05d.gguf" % (i, total))
            for i in range(1, total + 1)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gguf", required=True, help="the model's shard 1")
    a = ap.parse_args()
    first = pathlib.Path(a.gguf).absolute()
    for p in shards(first):
        if not p.is_file():
            print("missing shard: %s" % p, file=sys.stderr)
            return 1
        if any(t.name == PLE_TENSOR for t in G.GGUFFile(p).tensors):
            print(str(p))
            return 0
    print("no shard of %s holds %s" % (first.name, PLE_TENSOR), file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
