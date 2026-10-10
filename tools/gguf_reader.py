"""Minimal GGUF v3 header reader - no ggml, no gguf-py.

Written because the `gguf` PyPI package cannot open this artifact: its `GGMLQuantizationType`
enum has no member for type 42 (`Q2_0`), which is newer than the library. That is itself a P0.S6
finding - the format this engine is specialized for is ahead of the standard tooling.

This is the reference implementation for `src/artifact/` (architecture §15: "GGUF v3 reader (mmap,
no ggml dependency)"). It parses the header only; tensor data is never read.
"""
from __future__ import annotations

import dataclasses
import pathlib
import struct
from typing import Any

GGUF_MAGIC = 0x46554747  # "GGUF" little-endian

# ggml_type values. 42 = Q2_0, the GSQ-RCO routed-expert encoding, absent from gguf-py as of 0.19.
GGML_TYPES: dict[int, str] = {
    0: "F32", 1: "F16", 2: "Q4_0", 3: "Q4_1", 4: "Q4_2", 5: "Q4_3", 6: "Q5_0", 7: "Q5_1",
    8: "Q8_0", 9: "Q8_1", 10: "Q2_K", 11: "Q3_K", 12: "Q4_K", 13: "Q5_K", 14: "Q6_K",
    15: "Q8_K", 16: "IQ2_XXS", 17: "IQ2_XS", 18: "IQ3_XXS", 19: "IQ1_S", 20: "IQ4_NL",
    21: "IQ3_S", 22: "IQ2_S", 23: "IQ4_XS", 24: "I8", 25: "I16", 26: "I32", 27: "I64",
    28: "F64", 29: "IQ1_M", 30: "BF16", 31: "Q4_0_4_4", 32: "Q4_0_4_8", 33: "Q4_0_8_8",
    34: "TQ1_0", 35: "TQ2_0", 36: "IQ4_NL_4_4", 37: "IQ4_NL_4_8", 38: "IQ4_NL_8_8",
    39: "MXFP4", 40: "NVFP4", 41: "Q4_0_8_8", 42: "Q2_0",
}

# GGUF metadata value type ids
GGUF_META = {
    0: ("u8", 1), 1: ("i8", 1), 2: ("u16", 2), 3: ("i16", 2), 4: ("u32", 4), 5: ("i32", 4),
    6: ("f32", 4), 7: ("bool", 1), 8: ("string", None), 9: ("array", None),
    10: ("u64", 8), 11: ("i64", 8), 12: ("f64", 8),
}

# ggml block geometry for the encodings this model uses: (block elements, bytes per block)
# This is what makes a per-tensor byte count checkable, and it is the contract the kernels share.
BLOCK_GEOMETRY: dict[str, tuple[int, int]] = {
    "F32": (1, 4), "F16": (1, 2), "BF16": (1, 2), "F64": (1, 8),
    "Q4_0": (32, 18), "Q4_1": (32, 20), "Q5_0": (32, 22), "Q5_1": (32, 24),
    "Q8_0": (32, 34), "Q8_1": (32, 36),
    "Q2_K": (256, 84), "Q3_K": (256, 110), "Q4_K": (256, 144), "Q5_K": (256, 176),
    "Q6_K": (256, 210), "Q8_K": (256, 292),
    "IQ2_XXS": (256, 66), "IQ2_XS": (256, 74), "IQ3_XXS": (256, 98), "IQ1_S": (256, 50),
    "IQ4_NL": (32, 18), "IQ3_S": (256, 110), "IQ2_S": (256, 82), "IQ4_XS": (256, 136),
    "IQ1_M": (256, 56), "Q2_0": (64, 18), "MXFP4": (32, 17), "NVFP4": (64, 36),
}


@dataclasses.dataclass
class TensorInfo:
    name: str
    shape: list[int]
    type_id: int
    type_name: str
    offset: int

    @property
    def elements(self) -> int:
        n = 1
        for d in self.shape:
            n *= d
        return n

    def expected_bytes(self) -> int | None:
        geom = BLOCK_GEOMETRY.get(self.type_name)
        if geom is None:
            return None
        block_elems, block_bytes = geom
        # GGUF blocks may NEVER cross a row. A shape [128, 2] Q6_K has
        # 256 total values but each 128-element row is INVALID (QK_K=256).
        if not self.shape or any(d <= 0 for d in self.shape) or self.shape[0] % block_elems:
            return None
        return self.elements // block_elems * block_bytes


class GGUFFile:
    def __init__(self, path: pathlib.Path):
        self.path = pathlib.Path(path)
        self.metadata: dict[str, Any] = {}
        self.tensors: list[TensorInfo] = []
        self.version = 0
        self.alignment = 32
        self.file_bytes = self.path.stat().st_size
        with self.path.open("rb") as fh:
            self._parse(fh)
        self.data_start = self._data_start

    # ------------------------------------------------------------------ internals
    def _read(self, fh, size: int) -> bytes:
        if size < 0 or size > self.file_bytes - fh.tell():
            raise ValueError(f"{self.path.name}: GGUF header exceeds file bounds")
        raw = fh.read(size)
        if len(raw) != size:
            raise ValueError(f"{self.path.name}: truncated GGUF header")
        return raw

    def _parse(self, fh) -> None:
        magic = struct.unpack("<I", self._read(fh, 4))[0]
        if magic != GGUF_MAGIC:
            raise ValueError(f"{self.path.name}: not a GGUF file (magic {magic:#x})")
        self.version, n_tensors, n_kv = struct.unpack("<IQQ", self._read(fh, 20))
        if self.version != 3:
            raise ValueError(f"{self.path.name}: GGUF v{self.version}, this reader handles v3")
        remaining = self.file_bytes - fh.tell()
        if n_kv > remaining // 13 or n_kv > (1 << 20) or n_tensors > remaining // 32 or n_tensors > (1 << 22):
            raise ValueError(f"{self.path.name}: implausible GGUF directory count")
        for _ in range(n_kv):
            key = self._str(fh)
            if key in self.metadata:
                raise ValueError(f"{self.path.name}: duplicate metadata key {key!r}")
            self.metadata[key] = self._value(fh)
        names: set[str] = set()
        for _ in range(n_tensors):
            name = self._str(fh)
            if name in names:
                raise ValueError(f"{self.path.name}: duplicate tensor name {name!r}")
            names.add(name)
            (n_dims,) = struct.unpack("<I", self._read(fh, 4))
            if not (1 <= n_dims <= 4):
                raise ValueError(f"{self.path.name}: invalid tensor rank")
            shape = list(struct.unpack(f"<{n_dims}Q", self._read(fh, 8 * n_dims)))
            type_id, offset = struct.unpack("<IQ", self._read(fh, 12))
            self.tensors.append(TensorInfo(name, shape, type_id,
                                           GGML_TYPES.get(type_id, f"type{type_id}"), offset))
        align = self.metadata.get("general.alignment", 32)
        if type(align) is not int or not (0 < align <= (1 << 20)) or (align & (align - 1)):
            raise ValueError(f"{self.path.name}: invalid general.alignment")
        self.alignment = align
        pos = fh.tell()
        self._data_start = pos + ((-pos) % self.alignment)
        if self._data_start > self.file_bytes:
            raise ValueError(f"{self.path.name}: GGUF data start beyond EOF")

    def _str(self, fh) -> str:
        (n,) = struct.unpack("<Q", self._read(fh, 8))
        return self._read(fh, n).decode("utf-8", "replace")

    def _value(self, fh):
        (t,) = struct.unpack("<I", self._read(fh, 4))
        if t not in GGUF_META:
            raise ValueError(f"{self.path.name}: unsupported GGUF metadata value type {t}")
        name, size = GGUF_META[t]
        if name == "string":
            return self._str(fh)
        if name == "array":
            (et,) = struct.unpack("<I", self._read(fh, 4))
            (count,) = struct.unpack("<Q", self._read(fh, 8))
            if et not in GGUF_META or count > (1 << 24) or et == 9:
                raise ValueError(f"{self.path.name}: invalid GGUF metadata array")
            ename, esize = GGUF_META[et]
            if ename == "string":
                return [self._str(fh) for _ in range(count)]
            fmt = {"u8": "B", "i8": "b", "u16": "H", "i16": "h", "u32": "I", "i32": "i",
                   "f32": "f", "bool": "?", "u64": "Q", "i64": "q", "f64": "d"}[ename]
            raw = self._read(fh, esize * count)
            return list(struct.unpack(f"<{count}{fmt}", raw))
        fmt = {"u8": "B", "i8": "b", "u16": "H", "i16": "h", "u32": "I", "i32": "i",
               "f32": "f", "bool": "?", "u64": "Q", "i64": "q", "f64": "d"}[name]
        return struct.unpack(f"<{fmt}", self._read(fh, size))[0]

    def validate_native_payload_layout(self) -> None:
        """Mirror C++ validate_native_tensor_layout for strict Q6_K/Q8_0 import.

        Not called on opening arbitrary GGUFs: some diagnostics only need headers
        and may contain quantization types not supported by native dense.
        """
        spans: list[tuple[int, int, str]] = []
        payload = self.file_bytes - self.data_start
        for t in self.tensors:
            if t.offset % self.alignment:
                raise ValueError(f"{self.path.name}: unaligned tensor offset {t.name}")
            n = t.expected_bytes()
            if n is None or n <= 0:
                raise ValueError(f"{self.path.name}: invalid tensor block geometry {t.name}")
            if t.offset > payload or n > payload - t.offset:
                raise ValueError(f"{self.path.name}: truncated tensor {t.name}")
            spans.append((t.offset, n, t.name))
        spans.sort()
        for (old_offset, old_size, old_name), (offset, _, name) in zip(spans, spans[1:]):
            if old_size > offset - old_offset:
                raise ValueError(f"{self.path.name}: overlapping tensor payloads {old_name} and {name}")

    # ------------------------------------------------------------------ helpers
    def by_type(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for t in self.tensors:
            out[t.type_name] = out.get(t.type_name, 0) + 1
        return dict(sorted(out.items(), key=lambda kv: -kv[1]))

    def find(self, needle: str) -> list[TensorInfo]:
        return [t for t in self.tensors if needle in t.name]
