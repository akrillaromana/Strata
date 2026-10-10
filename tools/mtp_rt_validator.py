"""CPU-only verification of an MTP runtime directory before publication/use.

The CUDA loader has its own independent C++ dense index verifier. This
preflight checks the generated expert blob, all dense index ranges and the
required Q8_0 projections without mapping large weight payloads into RAM.
"""
from __future__ import annotations

from pathlib import Path

try:
    from .mtp_runtime_contract import Q8_NAMES
    from .mtp_native_layout import validate_native_manifest
except ImportError:
    from mtp_runtime_contract import Q8_NAMES
    from mtp_native_layout import validate_native_manifest

H, FF, NE = 2560, 640, 512
EXPERT_BLOB = 3 * (H * FF * 18 // 64)
REQUIRED = Q8_NAMES - {'self_attn.indexer.index_qk_proj.weight'}


def validate_runtime(directory: Path, *, expected_expert_bytes: int = EXPERT_BLOB * NE,
                     native_geometry: tuple[int, int, int] = (NE, H, FF)) -> list[dict]:
    directory = Path(directory)
    dense_data = directory / 'dense.bin'
    dense_index = directory / 'dense.txt'
    expert_data = directory / 'experts.bin'
    if not all(p.is_file() and not p.is_symlink() for p in (dense_data, dense_index, expert_data)):
        raise ValueError('incomplete or symlinked MTP runtime files')
    if (directory / 'experts.txt').exists() or (directory / 'experts.txt').is_symlink():
        validate_native_manifest(directory, expert_data.stat().st_size,
                                 n=native_geometry[0], h=native_geometry[1], ff=native_geometry[2])
    elif expert_data.stat().st_size != expected_expert_bytes:
        raise ValueError('incorrect Q2_0 MTP experts.bin byte length')
    size = dense_data.stat().st_size
    if size <= 0:
        raise ValueError('empty MTP dense.bin')
    raw = dense_index.read_bytes()
    if len(raw) > 256 * 1024 or not raw.endswith(b'\n'):
        raise ValueError('oversized or truncated MTP dense.txt')
    lines = raw.decode('utf-8').splitlines()
    if len(lines) > 256:
        raise ValueError('too many MTP dense entries')
    result = []
    seen = set()
    for line in lines:
        if not line or len(line) > 1024:
            raise ValueError('empty or oversized dense index line')
        fields = line.split()
        if len(fields) != 6:
            raise ValueError('invalid dense index column count')
        name, kind, nr, nc, start, length = fields
        if name in seen or len(name) > 200 or not name or any(x in name for x in ('..', '/', '\\')):
            raise ValueError('duplicate or unsafe dense tensor name')
        seen.add(name)
        ints = (nr, nc, start, length)
        if any(not s.isascii() or not s.isdecimal() for s in ints):
            raise ValueError('non-decimal dense index integer')
        rows, cols, offset, nbytes = map(int, ints)
        if rows < 1 or cols < 1 or rows > (2**63 - 1) or cols > (2**63 - 1):
            raise ValueError('invalid dense dimensions')
        if rows > (2**64 - 1) // cols:
            raise ValueError('dense element count overflow')
        elements = rows * cols
        if kind == 'q8_0':
            if cols % 32:
                raise ValueError('invalid Q8_0 inner dimension')
            expected = elements // 32 * 34
        elif kind in ('bf16', 'f32'):
            expected = elements * (2 if kind == 'bf16' else 4)
        else:
            raise ValueError('unknown dense tensor kind')
        if expected != nbytes or offset % 256 or offset > size or nbytes > size - offset:
            raise ValueError('invalid dense tensor size, alignment or range')
        result.append({'name': name, 'kind': kind, 'start': offset, 'end': offset + nbytes})
    result.sort(key=lambda x: x['start'])
    if any(a['end'] > b['start'] for a, b in zip(result, result[1:])):
        raise ValueError('overlapping MTP dense tensors')
    found = {t['name'] for t in result if t['kind'] == 'q8_0'}
    if REQUIRED - found:
        raise ValueError('missing required Q8_0 projections: ' + ', '.join(sorted(REQUIRED - found)))
    return result
