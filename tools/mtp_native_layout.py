"""Byte-exact MTP native expert runtime layout; mirrored by C++ mtp_native_layout.hpp.

experts.txt: mtp_native_experts_v1 <gate-kind> <down-kind> <count> <hidden> <ff>\n
experts.bin: per expert, gate_up (gate rows then up rows), then down;
             original physical BF16/Q8_0 row bytes in GGUF order.
"""
from __future__ import annotations

from pathlib import Path

H, FF, NE = 2560, 640, 512
KINDS = {'bf16': (30, 64), 'q8_0': (8, 34)}  # physical bytes per 32 weights


def native_layout(gate: str, down: str, n: int = NE, h: int = H, ff: int = FF) -> dict:
    if gate not in KINDS or down not in KINDS or not all(isinstance(v, int) and not isinstance(v, bool) for v in (n, h, ff)):
        raise ValueError('invalid native expert format')
    if n < 1 or h < 32 or ff < 32 or h % 32 or ff % 32 or any(v > 2**63 - 1 for v in (n, h, ff)):
        raise ValueError('invalid native expert geometry')
    gu = 2 * ff * h // 32 * KINDS[gate][1]
    dn = h * ff // 32 * KINDS[down][1]
    stride = gu + dn
    if n * stride > 2**64 - 1 or gu > 2**64 - 1 or dn > 2**64 - 1:
        raise ValueError('native expert runtime overflows 64 bits')
    return {'gate_kind': gate, 'down_kind': down, 'count': n, 'hidden': h, 'ff': ff,
            'gate_bytes': gu, 'down_bytes': dn, 'expert_bytes': stride, 'total_bytes': n * stride}


def write_native_manifest(folder: Path, layout: dict) -> None:
    (folder / 'experts.txt').write_text('mtp_native_experts_v1 '
        f"{layout['gate_kind']} {layout['down_kind']} {layout['count']} "
        f"{layout['hidden']} {layout['ff']}\n", encoding='ascii')


def validate_native_manifest(folder: Path, expert_size: int, *, n=NE, h=H, ff=FF) -> dict:
    path = folder / 'experts.txt'
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 256:
        raise ValueError('missing, symlinked or oversized experts.txt')
    data = path.read_bytes()
    if not data.endswith(b'\n') or data.count(b'\n') != 1:
        raise ValueError('native expert manifest must be one terminated line')
    try:
        fields = data.decode('ascii').split()
    except UnicodeError as exc:
        raise ValueError('non-ASCII native expert manifest') from exc
    if len(fields) != 6 or fields[0] != 'mtp_native_experts_v1':
        raise ValueError('invalid native expert manifest')
    if any(not s.isascii() or not s.isdecimal() for s in fields[3:]):
        raise ValueError('non-decimal native expert geometry')
    if (int(fields[3]), int(fields[4]), int(fields[5])) != (n, h, ff):
        raise ValueError('native expert geometry mismatch')
    layout = native_layout(fields[1], fields[2], n=n, h=h, ff=ff)
    if layout['total_bytes'] != expert_size:
        raise ValueError('native experts.bin size mismatch')
    return layout
