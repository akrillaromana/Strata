"""Explicit preparation of original Unsloth BF16/Q8_0 MTP GGUF weights.

There are two distinct expert routes. `--experts native` preserves original
routed-expert BF16/Q8_0 bits for the native drafter CUDA path. `--experts q2_0`
remains the older opt-in lossy conversion; NEVER an automatic fallback.
To opt into the lossy route, pass this exact switch:

    python tools/mtp_original_rt.py --gguf SOURCE.gguf --out NEW_DIRECTORY \\
        --experts q2_0 --allow-lossy-expert-conversion

The Q8_0 *dense projections* are copied without requantization; BF16 dense
projections are quantized to Q8_0. The 512 routed experts are processed ONE
AT A TIME, then converted to Q2_0 using Strata's explicit MSE quantizer.
Runs offline: never starts models, modifies GGUF inputs, or touches E:/R:.
Use --experts native for lossless BF16/Q8_0 expert storage and the new CUDA
native routed-expert path; --experts q2_0 requires explicit lossy consent.
Both output formats use --mtp with matching metadata; original GGUF isn't a runtime.

GGUF variants missing the complete routed-expert tensors (for example a
shared-only file) are rejected rather than merged with an unrelated source.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np

try:
    from .mtp_source_contract import H, FF, NE, source_contract, source_to_f32, validate_q8_payload
    from .mtp_runtime_contract import EXPERT_NAMES, Q8_NAMES
    from .mtp_native_layout import native_layout, write_native_manifest
except ImportError:
    from mtp_source_contract import H, FF, NE, source_contract, source_to_f32, validate_q8_payload
    from mtp_runtime_contract import EXPERT_NAMES, Q8_NAMES
    from mtp_native_layout import native_layout, write_native_manifest


def prepare(reader, dest: Path, q2, make_blob, dense_q8, *, sample_count: int = 8) -> dict:
    """Stream compatible original GGUF data into an initially empty dir.

    `reader` may be an mmap-backed gguf.GGUFReader. Dependency-injection makes
    the logic testable without optional gguf-py or allocating 512 experts.
    """
    source_contract(reader.tensors)
    by_name = {str(t.name): t for t in reader.tensors}
    gu, dn = (by_name[name] for name in EXPERT_NAMES)
    summary = {'source_expert_quantization': {'gate_up': 'Q8_0' if int(gu.tensor_type) == 8 else 'BF16',
                                             'down': 'Q8_0' if int(dn.tensor_type) == 8 else 'BF16'},
               'runtime_expert_quantization': 'Q2_0', 'conversion': 'EXPLICIT_LOSSY',
               'expert_count': NE, 'dense_tensor_count': 0, 'sample_relative_rms_error': None}
    (dest / 'source_policy.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    errors = []
    expected_blob = 3 * (H * FF * 18 // 64)
    with (dest / 'experts.bin').open('wb') as fp:
        for expert in range(NE):
            gate = source_to_f32(_slice_expert(gu, expert), H)
            down = source_to_f32(_slice_expert(dn, expert), FF)
            qgate = np.asarray(q2(gate), dtype=np.uint8).reshape(2 * FF, H // 64 * 18)
            qdown = np.asarray(q2(down), dtype=np.uint8).reshape(H, FF // 64 * 18)
            blob = make_blob(qgate, qdown)
            if len(blob) != expected_blob:
                raise ValueError(f'wrong converted MTP expert blob size at index {expert}')
            fp.write(blob)
            if expert < sample_count:
                # Reconstruct packed Q2_0 blocks from the actual stored fp16 scale.
                for original, packed in ((gate, qgate), (down, qdown)):
                    decoded = dequant_q2(packed, original.shape)
                    base = float(np.linalg.norm(original.astype(np.float64)))
                    err = float(np.linalg.norm((decoded - original).astype(np.float64)))
                    errors.append(err / max(base, 1e-12))
    if (dest / 'experts.bin').stat().st_size != expected_blob * NE:
        raise ValueError('wrong expert output file size')
    summary['sample_relative_rms_error'] = round(sum(errors) / len(errors), 8) if errors else None

    offset, dense_count = _write_dense(by_name, dest, dense_q8)
    summary['dense_tensor_count'] = dense_count
    summary['dense_bytes'] = offset
    summary['experts_bytes'] = expected_blob * NE
    (dest / 'source_policy.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    return summary


def _write_dense(by_name, dest: Path, dense_q8):
    offset, index = 0, []
    with (dest / 'dense.bin').open('wb') as fp:
        for name, tensor in by_name.items():
            if name in EXPERT_NAMES:
                continue
            short = name.removeprefix('mtp.').removeprefix('layers.0.')
            data = np.asarray(tensor.data)
            kind_id = int(tensor.tensor_type)
            if kind_id == 0:
                vals = np.asarray(data, dtype=np.float32)
                if not np.isfinite(vals).all():
                    raise ValueError(f'{name}: non-finite F32 norm')
                raw = (vals + np.float32(1)).astype('<f4').tobytes()
                kind, rows, cols = 'f32', 1, vals.size
            elif short in Q8_NAMES:
                if kind_id == 8:
                    validate_q8_payload(data)
                    raw = data.tobytes(order='C')  # exact Q8_0 blocks
                    rows, cols = data.shape[0], data.shape[1] // 34 * 32
                else:
                    rows, cols = data.shape
                    raw = dense_q8(source_to_f32(tensor, cols))
                kind = 'q8_0'
            elif kind_id == 30:
                # Other BF16 tensors are kept unchanged but still checked for
                # non-finite source values before GPU use.
                source_to_f32(tensor, data.shape[-1])
                rows, cols = data.reshape(data.shape[0], -1).shape
                raw = data.tobytes(order='C')
                kind = 'bf16'
            else:
                raise ValueError(f'{name}: unsupported dense kind {kind_id}')
            if not raw:
                raise ValueError(f'{name}: empty encoded tensor')
            pad = (-offset) % 256
            fp.write(b'\0' * pad)
            offset += pad
            fp.write(raw)
            index.append(f'{short} {kind} {rows} {cols} {offset} {len(raw)}')
            offset += len(raw)
    (dest / 'dense.txt').write_text('\n'.join(index) + '\n', encoding='utf-8')
    return offset, len(index)


def prepare_native(reader, dest: Path, dense_q8) -> dict:
    """Emit original GGUF BF16/Q8_0 expert bit patterns with no expert requantization."""
    source_contract(reader.tensors)
    by_name = {str(t.name): t for t in reader.tensors}
    gate, down = (by_name[name] for name in EXPERT_NAMES)
    gate_kind = 'q8_0' if int(gate.tensor_type) == 8 else 'bf16'
    down_kind = 'q8_0' if int(down.tensor_type) == 8 else 'bf16'
    layout = native_layout(gate_kind, down_kind, NE, H, FF)
    # Each original matrix is contiguous in GGUF physical row order.
    with (dest / 'experts.bin').open('wb') as fp:
        for expert in range(NE):
            for tensor, kind, required in ((gate, gate_kind, layout['gate_bytes']),
                                            (down, down_kind, layout['down_bytes'])):
                original = np.asarray(tensor.data[expert])
                if kind == 'q8_0':
                    validate_q8_payload(original)
                else:
                    source_to_f32(_slice_expert(tensor, expert), H if tensor is gate else FF)
                payload = original.tobytes(order='C')
                if len(payload) != required:
                    raise ValueError('MTP native expert row payload mismatch')
                fp.write(payload)
    if (dest / 'experts.bin').stat().st_size != layout['total_bytes']:
        raise ValueError('incomplete native MTP expert output')
    write_native_manifest(dest, layout)
    dense_bytes, dense_count = _write_dense(by_name, dest, dense_q8)
    summary = {'conversion': 'NATIVE_LOSSLESS_EXPERTS',
               'source_expert_quantization': {'gate_up': gate_kind.upper(), 'down': down_kind.upper()},
               'runtime_expert_quantization': 'NATIVE_BF16_Q8_0',
               'expert_count': NE, 'dense_tensor_count': dense_count,
               'dense_bytes': dense_bytes, 'experts_bytes': layout['total_bytes'],
               'sample_relative_rms_error': 0.0}
    (dest / 'source_policy.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    return summary


def _slice_expert(tensor, index):
    """Keep source metadata but expose just one expert slice for mmap streaming."""
    from types import SimpleNamespace
    return SimpleNamespace(name=tensor.name, tensor_type=tensor.tensor_type, data=tensor.data[index])


def dequant_q2(data: np.ndarray, shape: tuple[int, ...]) -> np.ndarray:
    blocks = np.asarray(data, dtype=np.uint8).reshape(-1, 18)
    scales = np.ascontiguousarray(blocks[:, :2]).view('<f2').astype(np.float32).reshape(-1, 1)
    codes = blocks[:, 2:]
    bits = np.stack([((codes >> shift) & 3) for shift in (0, 2, 4, 6)], axis=-1)
    return ((bits.reshape(-1, 64).astype(np.float32) - 1) * scales).reshape(shape)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--gguf', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--experts', choices=['q2_0', 'native'], required=True,
                        help='native keeps original BF16/Q8_0 expert bits; q2_0 is explicitly lossy')
    parser.add_argument('--allow-lossy-expert-conversion', action='store_true',
                        help='mandatory acknowledgement of BF16/Q8_0 to Q2_0 quality loss')
    args = parser.parse_args(argv)
    if args.experts == 'q2_0' and not args.allow_lossy_expert_conversion:
        parser.error('Q2_0 expert conversion is lossy: specify --allow-lossy-expert-conversion')
    if args.experts == 'native' and args.allow_lossy_expert_conversion:
        parser.error('native expert conversion is lossless; do not specify --allow-lossy-expert-conversion')
    if not args.gguf.is_file() or args.out.exists() or args.out.is_symlink() or not args.out.parent.is_dir():
        parser.error('source must exist, destination must NOT exist, parent must exist')
    if args.gguf.resolve() == args.out.resolve():
        parser.error('source and destination must be different')

    # Optional gguf-py is required only to run a conversion, not for offline tests.
    try:
        from ._paths import add_gguf_py
    except ImportError:
        from _paths import add_gguf_py
    add_gguf_py()
    import gguf
    try:
        from .mtp_pack import q2_0
        from .mtp_rt import blob_of, q8_0
    except ImportError:
        from mtp_pack import q2_0
        from mtp_rt import blob_of, q8_0
    reader = gguf.GGUFReader(str(args.gguf))
    source_contract(reader.tensors)  # fail before creating any output directory
    with TemporaryDirectory(prefix='mtp-prepare-', dir=str(args.out.parent)) as temporary:
        folder = Path(temporary) / 'runtime'
        folder.mkdir()
        result = (prepare_native(reader, folder, q8_0) if args.experts == 'native'
                  else prepare(reader, folder, q2_0, blob_of, q8_0))
        # The engine's C++ runtime uses precisely these files; keep a portable
        # Python verifier too (must not assume a GPU). Imported lazily.
        try:
            from .mtp_rt_validator import validate_runtime
        except ImportError:
            from mtp_rt_validator import validate_runtime
        validate_runtime(folder)
        os.rename(folder, args.out)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
