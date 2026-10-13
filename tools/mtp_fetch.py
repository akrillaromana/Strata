"""tools/mtp_fetch.py - plan v0.3, P0.3/P6: the MTP block from the BF16 checkpoint, without the checkpoint.

The GSQ-RCO GGUF ships no MTP head. The BF16 checkpoint (Qwen/Qwen3.8-Flash-Next, 360 GB in 131 shards) does:
31 `mtp.*` tensors scattered over 28 shards. Safetensors puts a JSON header (name -> dtype, shape, byte range)
at the start of each shard, so HTTP range requests can read the headers and then only the MTP tensors.

    python tools/mtp_fetch.py inventory --out DIR          # headers only (a few KB per shard)
    python tools/mtp_fetch.py fetch --out DIR [--only SUBSTR]  # the MTP tensors themselves, resumable
    python tools/mtp_fetch.py verify --out DIR             # names and exact byte sizes (exit 3: bad ones)

`fetch` writes one raw file per tensor plus `mtp-manifest.json` (dtype, shape, source shard, byte range,
name and exact byte size). It never downloads anything but the ranges named in the headers. Nothing here runs a model.

#327: a mirror or proxy that ignores the Range header answers 200 with the whole shard - its JSON header and
unrelated tensors - and a proxy may cut that to the requested length. A range read therefore still requires
a 206 whose Content-Range is exactly the requested range; saved files are accepted by filename and exact byte size.
"""
import argparse
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.request

# #214: a fixed commit of the checkpoint (its `sha` from https://huggingface.co/api/models/Qwen/Qwen3.8-Flash-Next
# on 2026-09-30), so every install reads the same tensors; STRATA_MTP_REVISION overrides it (e.g. main).  When the
# repository no longer has it, the current files are read instead, with a message (resolve_repo).
PINNED_REVISION = "de4b8e4d43b917e7706784d8bb445c9af86a3540"
REVISION = os.environ.get("STRATA_MTP_REVISION") or PINNED_REVISION
# #495: HF_ENDPOINT (a mirror, e.g. https://hf-mirror.com) serves the same revision.
HF_ENDPOINT = (os.environ.get("HF_ENDPOINT") or "").strip().rstrip("/") or "https://huggingface.co"
REPO = HF_ENDPOINT + "/Qwen/Qwen3.8-Flash-Next/resolve/%s/" % REVISION
PINNED = HF_ENDPOINT + "/Qwen/Qwen3.8-Flash-Next/resolve/%s/" % PINNED_REVISION
DTYPE_BYTES = {"BF16": 2, "F16": 2, "F32": 4, "F8_E4M3": 1, "I64": 8, "I32": 4}
BAD = 3                                             # `verify`'s exit code: a tensor is missing or corrupt

# File identity policy: filename + exact byte size; no SHA computation.
def get(url, start=None, end=None, retries=4):
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "strata-mtp-fetch"})
            if start is not None:
                req.add_header("Range", "bytes=%d-%d" % (start, end))
            with urllib.request.urlopen(req, timeout=120) as r:
                if start is not None:
                    check_range(r.status, r.headers.get("Content-Range"), start, end)
                data = r.read()
            if start is not None and len(data) != end - start + 1:
                raise IOError("short range read: %d of %d" % (len(data), end - start + 1))
            return data
        except Exception as e:  # network errors are retried, then surfaced
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)
            print("retry %s: %s" % (url, e), file=sys.stderr)


def check_range(status, content_range, start, end):
    """#327: a range read is only what was asked for when the server says so: 206 and `bytes START-END/...`."""
    if status != 206:
        raise IOError("range request not honoured: HTTP %s instead of 206 (a mirror or proxy that ignores the Range "
                      "header sends the whole file)" % status)
    want = "bytes %d-%d/" % (start, end)
    if not (content_range or "").strip().startswith(want):
        raise IOError("range request answered with Content-Range %r, not %s..." % (content_range, want))


def pinned():
    """Whether this run reads the pinned checkpoint revision."""
    return REPO == PINNED


def resolve_repo():
    """REPO, or the repository's current files when the pinned revision is gone from it (a 404 on its index)."""
    global REPO
    try:
        req = urllib.request.Request(REPO + "model.safetensors.index.json", method="HEAD",
                                     headers={"User-Agent": "strata-mtp-fetch"})
        urllib.request.urlopen(req, timeout=120).close()
    except urllib.error.HTTPError as e:
        if e.code == 404 and "/resolve/main/" not in REPO:
            print("the checkpoint's pinned revision %s is gone: reading its current files (main)" % REVISION,
                  file=sys.stderr)
            REPO = REPO.replace("/resolve/%s/" % REVISION, "/resolve/main/")
    except OSError:
        pass                                        # no answer: get() retries and reports it
    return REPO


def shard_header(shard):
    url = REPO + shard
    n = struct.unpack("<Q", get(url, 0, 7))[0]
    header = json.loads(get(url, 8, 8 + n - 1))
    return 8 + n, header


def inventory(out):
    index = json.loads(get(REPO + "model.safetensors.index.json"))["weight_map"]
    mtp = {k: v for k, v in index.items() if k.startswith("mtp.")}
    rows, total = [], 0
    for shard in sorted(set(mtp.values())):
        base, header = shard_header(shard)
        for name, meta in header.items():
            if name in mtp and mtp[name] == shard:
                a, b = meta["data_offsets"]
                rows.append(dict(name=name, shard=shard, dtype=meta["dtype"], shape=meta["shape"],
                                 start=base + a, end=base + b - 1, bytes=b - a))
                total += b - a
    missing = sorted(set(mtp) - set(r["name"] for r in rows))
    if missing:
        sys.exit("tensors named in the index but absent from their shard headers: %s" % missing)
    rows.sort(key=lambda r: r["name"])
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "mtp-inventory.json"), "w", encoding="utf-8") as f:
        json.dump(dict(repo=REPO, total_bytes=total, tensors=rows), f, indent=1)
    lines = ["# MTP block in the BF16 checkpoint", "", "%d tensors, %.3f GB, in %d shards." % (len(rows), total / 1e9, len(set(r["shard"] for r in rows))), "",
             "| tensor | dtype | shape | MB |", "|---|---|---|---:|"]
    for r in rows:
        lines.append("| `%s` | %s | %s | %.1f |" % (r["name"], r["dtype"], "x".join(map(str, r["shape"])), r["bytes"] / 1e6))
    text = "\n".join(lines) + "\n"
    with open(os.path.join(out, "mtp-inventory.md"), "w", encoding="utf-8") as f:
        f.write(text)
    print(text)
    return rows


def fetch(out, only):
    inv_path = os.path.join(out, "mtp-inventory.json")
    tdir = os.path.join(out, "tensors")
    inv = None
    if os.path.exists(inv_path):
        try:
            with open(inv_path, encoding="utf-8") as f:
                inv = json.load(f)
        except ValueError:
            inv = None
    # The byte ranges belong to one revision: an inventory read from another repository or revision is read again.
    same = isinstance(inv, dict) and inv.get("repo") == REPO
    rows = inv["tensors"] if same else inventory(out)
    os.makedirs(tdir, exist_ok=True)
    manifest = []
    chunk = 64 << 20
    for r in rows:
        if only and only not in r["name"]:
            continue
        path = os.path.join(tdir, r["name"] + ".bin")
        if os.path.exists(path) and os.path.getsize(path) != r["bytes"]:
            os.remove(path)
        have = os.path.getsize(path) if os.path.exists(path) else 0
        if have > r["bytes"]:
            os.remove(path)
            have = 0
        with open(path, "ab") as f:
            pos = r["start"] + have
            while pos <= r["end"]:
                end = min(pos + chunk - 1, r["end"])
                f.write(get(REPO + r["shard"], pos, end))
                pos = end + 1
                print("%s %.0f%%" % (r["name"], 100 * (pos - r["start"]) / r["bytes"]), file=sys.stderr)
        if os.path.getsize(path) != r["bytes"]:
            sys.exit("%s: size %d != %d" % (path, os.path.getsize(path), r["bytes"]))
        manifest.append(dict(r, file=os.path.relpath(path, out), identity_name=os.path.basename(path)))
    with open(os.path.join(out, "mtp-manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)


def verify(out):
    """Verify every fetched tensor by filename and exact byte size."""
    tdir = os.path.join(out, "tensors")
    manifest_path = os.path.join(out, "mtp-manifest.json")
    if not os.path.isdir(tdir) or not os.path.isfile(manifest_path):
        return []
    try:
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError, TypeError):
        return ["mtp-manifest.json"]
    bad = []
    for row in manifest:
        name = row.get("name")
        rel = row.get("file")
        expected = row.get("bytes")
        if not isinstance(name, str) or not isinstance(rel, str) or not isinstance(expected, int):
            bad.append(str(name or rel or "invalid-manifest-row"))
            continue
        path = os.path.join(out, rel)
        if (os.path.basename(path) != name + ".bin" or not os.path.isfile(path) or
                os.path.getsize(path) != expected):
            bad.append(name)
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["inventory", "fetch", "verify"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--only")
    a = ap.parse_args()
    if a.cmd == "verify":
        bad = verify(a.out)
        for name in bad:
            print("MTP tensor missing or corrupt: %s" % name, file=sys.stderr)
        sys.exit(BAD if bad else 0)
    resolve_repo()
    inventory(a.out) if a.cmd == "inventory" else fetch(a.out, a.only)


if __name__ == "__main__":
    main()
