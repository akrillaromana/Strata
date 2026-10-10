"""Offline checks and streaming tensor transforms for *original* Unsloth MTP GGUFs.

The installed MtpDrafter currently consumes Q2_0 routed expert blobs, not
native BF16/Q8_0 experts. This module refuses to disguise that distinction:
calling the optional converter requires an explicit lossy expert policy.
No weights or CUDA dependencies are necessary to import this module.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

try:
    from .mtp_runtime_contract import EXPERT_NAMES, Q8_NAMES
except ImportError:
    from mtp_runtime_contract import EXPERT_NAMES, Q8_NAMES

H, FF, NE = 2560, 640, 512
Q8_BLOCK_VALUES, Q8_BLOCK_BYTES = 32, 34


@dataclass(frozen=True)
class SourceTensor:
    name: str
    kind: int
    shape: tuple[int, ...]


def source_contract(tensors) -> dict[str, SourceTensor]:
    """Validate native BF16/Q8_0 experts and the dense graph before processing.

    Shapes here are physical NumPy shapes returned by gguf.GGUFReader, where
    Q8_0 stores 34 bytes for every 32 logical values in the final dimension.
    """
    found: dict[str, SourceTensor] = {}
    for tensor in tensors:
        name = str(tensor.name)
        if (not name.startswith('mtp.') or len(name) > 200 or '..' in name or
                '/' in name or '\\' in name or any(c.isspace() for c in name)):
            raise ValueError(f'unsafe MTP tensor name: {name!r}')
        if name in found or len(found) >= 256:
            raise ValueError(f'duplicate or excessive MTP tensor: {name}')
        shape = tuple(int(d) for d in tensor.data.shape)
        if not shape or any(d <= 0 for d in shape):
            raise ValueError(f'invalid source shape for {name}')
        found[name] = SourceTensor(name, int(tensor.tensor_type), shape)

    for name, rows, width in ((EXPERT_NAMES[0], 2 * FF, H), (EXPERT_NAMES[1], H, FF)):
        src = found.get(name)
        if src is None:
            raise ValueError(f'missing original MTP experts: {name}')
        if src.kind not in (8, 30):
            raise ValueError(f'{name}: expected source BF16 (30) or Q8_0 (8), got {src.kind}')
        cols = width * Q8_BLOCK_BYTES // Q8_BLOCK_VALUES if src.kind == 8 else width
        if src.shape != (NE, rows, cols):
            raise ValueError(f'{name}: invalid physical source geometry {src.shape}, '
                             f'expected {(NE, rows, cols)}')

    required = Q8_NAMES - {'self_attn.indexer.index_qk_proj.weight'}
    present = set()
    for name, src in found.items():
        if name in EXPERT_NAMES:
            continue
        short = name.removeprefix('mtp.').removeprefix('layers.0.')
        if short in Q8_NAMES:
            if src.kind not in (8, 30) or len(src.shape) != 2:
                raise ValueError(f'{name}: dense projection must be BF16 or Q8_0 matrix')
            if src.kind == 8 and src.shape[-1] % Q8_BLOCK_BYTES:
                raise ValueError(f'{name}: incomplete Q8_0 block')
            if src.kind == 30 and src.shape[-1] % Q8_BLOCK_VALUES:
                raise ValueError(f'{name}: BF16 projection lacks full Q8_0 blocks')
            present.add(short)
        elif src.kind == 0:
            if len(src.shape) != 1:
                raise ValueError(f'{name}: only one-dimensional F32 norms are supported')
        elif src.kind != 30:
            raise ValueError(f'{name}: unsupported non-projection source type {src.kind}')
    missing = required - present
    if missing:
        raise ValueError('missing MTP dense projections: ' + ', '.join(sorted(missing)))
    return found


def bf16_to_f32(x: np.ndarray) -> np.ndarray:
    """BF16 bit patterns to float32 without the numeric-cast precision bug."""
    raw = np.asarray(x)
    if raw.dtype.itemsize != 2:
        raise ValueError('BF16 source needs 16-bit storage')
    raw = raw.view(np.uint16)
    floats = (raw.astype(np.uint32) << 16).view(np.float32)
    if not np.isfinite(floats).all():
        raise ValueError('non-finite BF16 source weights')
    return floats


def q8_to_f32(packed: np.ndarray, *, logical_width: int) -> np.ndarray:
    """Decode ggml Q8_0: independent half scale and 32 signed int8 codes."""
    raw = np.asarray(packed, dtype=np.uint8)
    if raw.ndim < 1 or logical_width < 32 or logical_width % 32:
        raise ValueError('invalid logical Q8_0 tensor geometry')
    if raw.shape[-1] != logical_width // 32 * Q8_BLOCK_BYTES:
        raise ValueError('physical Q8_0 row width does not match logical shape')
    blocks = raw.reshape(-1, Q8_BLOCK_BYTES)
    scales = np.ascontiguousarray(blocks[:, :2]).view('<f2').astype(np.float32).reshape(-1, 1)
    if not np.isfinite(scales).all():
        raise ValueError('non-finite Q8_0 source scales')
    codes = blocks[:, 2:].view(np.int8).astype(np.float32)
    return (codes * scales).reshape(raw.shape[:-1] + (logical_width,))


def validate_q8_payload(packed: np.ndarray) -> None:
    """Reject malformed scales before forwarding unchanged Q8_0 dense blocks."""
    raw = np.asarray(packed, dtype=np.uint8)
    if raw.ndim < 1 or raw.shape[-1] % Q8_BLOCK_BYTES:
        raise ValueError('incomplete Q8_0 tensor payload')
    scales = np.ascontiguousarray(raw.reshape(-1, Q8_BLOCK_BYTES)[:, :2]).view('<f2')
    if not np.isfinite(scales).all():
        raise ValueError('non-finite Q8_0 source scales')


def source_to_f32(tensor, logical_width: int) -> np.ndarray:
    kind = int(tensor.tensor_type)
    if kind == 30:
        result = bf16_to_f32(np.asarray(tensor.data))
    elif kind == 8:
        result = q8_to_f32(np.asarray(tensor.data), logical_width=logical_width)
    else:
        raise ValueError(f'{tensor.name}: expected BF16 or Q8_0 source')
    if result.shape[-1] != logical_width:
        raise ValueError(f'{tensor.name}: logical width mismatch')
    return result
