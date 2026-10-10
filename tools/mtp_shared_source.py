"""Explicit, conservative union of one MTP GGUF and a *shared-only* companion.

GGUF files named ``shared`` are not assumed to be complete draft models. A
companion can ONLY supply missing shared-expert projections (and its optional
scalar gate); overlapping projections must be exactly byte-for-byte identical.
No routed expert or attention/FC weight is ever silently replaced.

Both GGUFReader instances must stay alive while the returned tensors are used:
GGUF tensor data may be backed by memory-mapped files. This module never
materializes all model weights in memory.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

try:
    from .mtp_runtime_contract import EXPERT_NAMES
    from . import mtp_source_contract as contract
except ImportError:
    from mtp_runtime_contract import EXPERT_NAMES
    import mtp_source_contract as contract

SHARED_PROJECTIONS = frozenset({
    'mtp.layers.0.mlp.shared_expert.gate_proj.weight',
    'mtp.layers.0.mlp.shared_expert.up_proj.weight',
    'mtp.layers.0.mlp.shared_expert.down_proj.weight',
})
SHARED_OPTIONAL = frozenset({'mtp.layers.0.mlp.shared_expert_gate.weight'})
SHARED_ALLOWED = SHARED_PROJECTIONS | SHARED_OPTIONAL


@dataclass
class JoinedMtpReader:
    tensors: list
    readers: tuple  # keep mapped GGUFReader objects alive for the entire conversion
    shared_added: tuple[str, ...]


def _same_payload(left, right) -> bool:
    """Compare physical tensor bytes, including BF16 NaN bit patterns."""
    if int(left.tensor_type) != int(right.tensor_type):
        return False
    a, b = np.asarray(left.data), np.asarray(right.data)
    if a.shape != b.shape or a.dtype != b.dtype:
        return False
    if not (a.flags.c_contiguous and b.flags.c_contiguous):
        raise ValueError(f'{left.name}: noncontiguous GGUF physical tensor')
    return bool(np.array_equal(a.view(np.uint8).reshape(-1), b.view(np.uint8).reshape(-1)))


def join_shared(primary, supplemental) -> JoinedMtpReader:
    """Validate an explicitly selected shared-only GGUF before any output I/O.

    Requires all three shared projection tensors in the companion. It must
    contain no extra tensors and must contribute at least one missing tensor.
    A companion with conflicting duplicates is rejected, never used to replace
    primary weights. This proves internal consistency, not common model origin.
    """
    original = list(primary.tensors)
    extras = list(supplemental.tensors)
    if not extras or len(extras) > len(SHARED_ALLOWED):
        raise ValueError('shared MTP GGUF has no supported or too many tensors')
    indexed: dict[str, object] = {}
    for item in original:
        name = str(item.name)
        if name in indexed:
            raise ValueError('duplicate primary MTP tensor: ' + name)
        indexed[name] = item
    supplemental_index: dict[str, object] = {}
    for item in extras:
        name = str(item.name)
        if name not in SHARED_ALLOWED:
            raise ValueError('companion is not shared-only; disallowed tensor: ' + name)
        if name in supplemental_index:
            raise ValueError('duplicate companion MTP tensor: ' + name)
        supplemental_index[name] = item
        kind = int(item.tensor_type)
        if kind not in (8, 30) or (name in SHARED_OPTIONAL and kind != 30):
            raise ValueError('companion shared tensor must be BF16/Q8_0 (BF16 scalar gate): ' + name)
        physical = np.asarray(item.data)
        h, ff = contract.H, contract.FF
        if name in SHARED_OPTIONAL:
            expected = (h,)
        else:
            out, width = (h, ff) if name.endswith('down_proj.weight') else (ff, h)
            if kind == 8 and width % 32:
                raise ValueError('shared Q8_0 projection width not block-aligned: ' + name)
            expected = (out, width // 32 * 34 if kind == 8 else width)
        if tuple(physical.shape) != expected or not physical.flags.c_contiguous:
            raise ValueError(f'invalid companion physical tensor layout: {name}: '
                             f'{physical.shape} != {expected}')
    absent = SHARED_PROJECTIONS - supplemental_index.keys()
    if absent:
        raise ValueError('companion misses shared projections: ' + ', '.join(sorted(absent)))
    added = []
    for name, value in supplemental_index.items():
        if name in indexed:
            if not _same_payload(indexed[name], value):
                raise ValueError('conflicting shared tensor; refusing to replace: ' + name)
        else:
            indexed[name] = value
            original.append(value)
            added.append(name)
    if not added:
        raise ValueError('shared companion contributes no missing tensors')
    if any(n in supplemental_index for n in EXPERT_NAMES):
        raise ValueError('shared companion cannot supply routed experts')
    # The combined reader must satisfy the normal full-runtime contract.
    contract.source_contract(original)
    return JoinedMtpReader(original, (primary, supplemental), tuple(sorted(added)))
