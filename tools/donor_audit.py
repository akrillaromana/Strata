#!/usr/bin/env python3
"""Compare a custom Strata FULL ZIP with an upstream donor ZIP, without extracting either.

    python tools/donor_audit.py --base Strata-custom-...zip --donor Strata-main.zip --tsv audit.tsv

The table is an inventory of differences, not a merge plan. Each changed runtime file needs review
against the fork's modifications. Model formats must not be inferred from filenames alone.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import zipfile
from pathlib import PurePosixPath


def manifest(path: str, root: str, max_file: int = 1 << 30) -> dict[str, str]:
    """SHA-256 each ZIP entry, rejecting duplicate/path-traversal names and implausible size."""
    entries: dict[str, str] = {}
    root = root.strip('/') + '/'
    with zipfile.ZipFile(path) as archive:
        for item in archive.infolist():
            name = item.filename
            if item.is_dir():
                continue
            if not name.startswith(root):
                raise ValueError(f'{path}: unexpected root: {name!r}')
            rel = name[len(root):]
            parts = PurePosixPath(rel).parts
            if not rel or rel.startswith('/') or '\\' in rel or any(p in ('..', '.') for p in parts):
                raise ValueError(f'{path}: unsafe ZIP path {name!r}')
            if rel in entries:
                raise ValueError(f'{path}: duplicate ZIP path {name!r}')
            if item.file_size > max_file:
                raise ValueError(f'{path}: file too large for source audit: {name!r}')
            h = hashlib.sha256()
            consumed = 0
            with archive.open(item) as stream:
                while chunk := stream.read(1 << 20):
                    consumed += len(chunk)
                    if consumed > max_file:
                        raise ValueError(f'{path}: excessive decompression: {name!r}')
                    h.update(chunk)
            entries[rel] = h.hexdigest()
    return entries


def classify(path: str) -> str:
    for prefix in ('src/', 'include/', 'sycl/', 'serve/', 'tools/', 'tests/', 'data/',
                   'bench/', 'docs/', '.github/'):
        if path.startswith(prefix):
            return prefix.rstrip('/')
    return 'root'


def compare(base: dict[str, str], donor: dict[str, str]) -> list[dict]:
    out = []
    for path in sorted(base.keys() | donor.keys()):
        if path not in base:
            status = 'donor_only'
        elif path not in donor:
            status = 'custom_only'
        elif base[path] != donor[path]:
            status = 'changed'
        else:
            status = 'identical'
        out.append({'file': path, 'area': classify(path), 'status': status,
                    'base_sha256': base.get(path, ''), 'donor_sha256': donor.get(path, '')})
    return out


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True, help='custom FULL ZIP')
    parser.add_argument('--donor', required=True, help='upstream donor ZIP')
    parser.add_argument('--base-root', default='Strata')
    parser.add_argument('--donor-root', default='Strata-main')
    parser.add_argument('--tsv', help='write full difference matrix to this path')
    parser.add_argument('--json', action='store_true', help='emit counts as JSON')
    args = parser.parse_args(argv)
    rows = compare(manifest(args.base, args.base_root), manifest(args.donor, args.donor_root))
    counts = {key: sum(r['status'] == key for r in rows)
              for key in ('identical', 'changed', 'donor_only', 'custom_only')}
    if args.tsv:
        with open(args.tsv, 'w', encoding='utf-8', newline='') as out:
            writer = csv.DictWriter(out, fieldnames=('file', 'area', 'status', 'base_sha256', 'donor_sha256'), delimiter='\t')
            writer.writeheader()
            writer.writerows(rows)
    print(json.dumps(counts, ensure_ascii=False) if args.json else ', '.join(f'{k}={v}' for k, v in counts.items()))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, zipfile.BadZipFile, OSError) as exc:
        sys.exit(f'donor audit failed: {exc}')
