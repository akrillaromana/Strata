"""Fail-closed validation of the packed MTP GGUF consumed by mtp_rt.py.

Strata's existing drafter uses Q2_0 expert blobs. An original Unsloth
BF16/Q8_0 (or shared) MTP GGUF must NOT be silently reinterpreted as that
format. This is an offline check, not CUDA compatibility certification.
"""
from __future__ import annotations

EXPERT_NAMES = (
    'mtp.layers.0.mlp.experts.gate_up_proj',
    'mtp.layers.0.mlp.experts.down_proj',
)
Q8_NAMES = frozenset({
    'fc_embedding.weight', 'fc_hidden.weight',
    'self_attn.q_proj.weight', 'self_attn.k_proj.weight',
    'self_attn.v_proj.weight', 'self_attn.o_proj.weight',
    'self_attn.indexer.index_qk_proj.weight',
    'mlp.shared_expert.gate_proj.weight', 'mlp.shared_expert.up_proj.weight',
    'mlp.shared_expert.down_proj.weight',
})


def packed_mtp_contract(tensors) -> None:
    """Check a gguf-py GGUFReader.tensors sequence before creating runtime files.

    t.tensor_type: 42=Q2_0, 30=BF16, 0=F32; t.data.shape is the
    *physical* packed tensor geometry returned by gguf-py.
    """
    indexed = {}
    for t in tensors:
        name = str(t.name)
        if name in indexed:
            raise ValueError(f'MTP GGUF has duplicate tensor: {name}')
        if not name.startswith('mtp.') or '/' in name or '..' in name or len(name) > 200:
            raise ValueError(f'MTP GGUF tensor name is not a safe mtp.* name: {name}')
        indexed[name] = t
    if len(indexed) < 11 or len(indexed) > 256:
        raise ValueError('MTP GGUF has an incomplete or oversized tensor directory')
    expected = ((512, 1280, 720), (512, 2560, 180))
    for name, physical_shape in zip(EXPERT_NAMES, expected):
        t = indexed.get(name)
        if t is None:
            raise ValueError(f'MTP GGUF missing routed experts: {name}')
        kind = int(t.tensor_type)
        if kind != 42:
            raise ValueError(f'{name}: routed experts have GGML type {kind}; this MTP runtime uses Q2_0 '
                             'expert blobs (type 42), NOT a direct BF16/Q8_0 GGUF input')
        if tuple(int(n) for n in t.data.shape) != physical_shape:
            raise ValueError(f'{name}: unexpected packed Q2_0 expert geometry')
    for name, t in indexed.items():
        if name in EXPERT_NAMES:
            continue
        kind = int(t.tensor_type)
        dims = tuple(int(n) for n in t.data.shape)
        if not dims or any(n < 1 for n in dims):
            raise ValueError(f'{name}: invalid physical shape')
        if kind == 0:
            if len(dims) != 1:
                raise ValueError(f'{name}: F32 tensor must be a norm vector')
        elif kind == 30:
            short = name.removeprefix('mtp.').removeprefix('layers.0.')
            if short in Q8_NAMES and (len(dims) < 2 or dims[-1] % 32):
                raise ValueError(f'{name}: BF16 projection cannot be packed into Q8_0 rows')
        else:
            raise ValueError(f'{name}: unsupported GGML type {kind}; existing runtime generator '
                             'accepts BF16 dense tensors or F32 norms only')
    for short in Q8_NAMES - {'self_attn.indexer.index_qk_proj.weight'}:
        if not any(n.removeprefix('mtp.').removeprefix('layers.0.') == short for n in indexed):
            raise ValueError(f'MTP GGUF missing required dense projection: {short}')
