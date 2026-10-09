from __future__ import annotations

import sys
from pathlib import Path
import gguf


META_SOURCE   = Path(sys.argv[1])
TENSOR_SOURCE = Path(sys.argv[2])
OUTPUT        = Path(sys.argv[3])

TENSOR_NAME = "per_layer_token_embd.weight"


print("META SOURCE  :", META_SOURCE)
print("TENSOR SOURCE:", TENSOR_SOURCE)
print("OUTPUT       :", OUTPUT)
print()


meta_reader = gguf.GGUFReader(META_SOURCE, "r")
tensor_reader = gguf.GGUFReader(TENSOR_SOURCE, "r")


# ------------------------------------------------------------
# Architecture comes from shard1
# ------------------------------------------------------------

arch_field = meta_reader.get_field(
    gguf.Keys.General.ARCHITECTURE
)

if arch_field is None:
    raise RuntimeError(
        "general.architecture отсутствует даже в shard1"
    )

arch = arch_field.contents()

if isinstance(arch, bytes):
    arch = arch.decode("utf-8")

print("architecture:", arch)


# ------------------------------------------------------------
# Actual PLE comes from shard2
# ------------------------------------------------------------

wanted = None

for tensor in tensor_reader.tensors:
    if tensor.name == TENSOR_NAME:
        wanted = tensor
        break


if wanted is None:
    print()
    print("per_layer tensors in shard2:")

    for tensor in tensor_reader.tensors:
        if "per_layer" in tensor.name.lower():
            print(" ", tensor.name)

    raise RuntimeError(
        f"{TENSOR_NAME} не найден в shard2"
    )


print()
print("SOURCE PLE:")
print(" name       :", wanted.name)
print(" type       :", wanted.tensor_type)
print(" n_elements :", wanted.n_elements)
print(" bytes      :", wanted.n_bytes)
print(
    " GiB        :",
    round(wanted.n_bytes / (1024**3), 3)
)
print(" GGUF shape :", wanted.shape.tolist())
print(" byte shape :", wanted.data.shape)
print()


# ------------------------------------------------------------
# Minimal standalone GGUF:
#
# ONLY:
#   general.architecture
#   per_layer_token_embd.weight
#
# No split metadata whatsoever.
# ------------------------------------------------------------

OUTPUT.parent.mkdir(
    parents=True,
    exist_ok=True
)

if OUTPUT.exists():
    OUTPUT.unlink()


writer = gguf.GGUFWriter(
    OUTPUT,
    arch=str(arch),
    endianess=meta_reader.endianess
)


# Preserve actual source alignment.
writer.data_alignment = tensor_reader.alignment


# Important:
# wanted.data is the raw quantized byte representation.
#
# raw_dtype tells GGUFWriter that these bytes are IQ4_NL
# (or whatever the original GGML quant type actually is).
#
# No dequantization takes place.
writer.add_tensor(
    wanted.name,
    wanted.data,
    raw_dtype=wanted.tensor_type,
    tensor_endianess=tensor_reader.endianess
)


writer.write_header_to_file()
writer.write_kv_data_to_file()
writer.write_tensors_to_file(progress=True)
writer.close()


print()
print("Standalone file written.")
print("file bytes:", OUTPUT.stat().st_size)
print(
    "file GiB  :",
    round(OUTPUT.stat().st_size / (1024**3), 3)
)


# ------------------------------------------------------------
# Reopen and verify
# ------------------------------------------------------------

print()
print("VERIFY:")

check = gguf.GGUFReader(
    OUTPUT,
    "r"
)

check_arch_field = check.get_field(
    gguf.Keys.General.ARCHITECTURE
)

if check_arch_field is None:
    raise RuntimeError(
        "Standalone PLE has no general.architecture"
    )

check_arch = check_arch_field.contents()

if isinstance(check_arch, bytes):
    check_arch = check_arch.decode("utf-8")


if str(check_arch) != str(arch):
    raise RuntimeError(
        f"Architecture changed: {check_arch} != {arch}"
    )


if len(check.tensors) != 1:
    raise RuntimeError(
        f"Expected 1 tensor, got {len(check.tensors)}"
    )


t = check.tensors[0]

if t.name != TENSOR_NAME:
    raise RuntimeError(
        f"Wrong tensor: {t.name}"
    )


if t.tensor_type != wanted.tensor_type:
    raise RuntimeError(
        f"Quantization changed: "
        f"{t.tensor_type} != {wanted.tensor_type}"
    )


if t.n_bytes != wanted.n_bytes:
    raise RuntimeError(
        f"Byte length changed: "
        f"{t.n_bytes} != {wanted.n_bytes}"
    )


split_fields = [
    field.name
    for field in check.fields.values()
    if field.name.startswith("split.")
]


if split_fields:
    raise RuntimeError(
        f"split metadata survived: {split_fields}"
    )


print(" architecture :", check_arch)
print(" tensor       :", t.name)
print(" type         :", t.tensor_type)
print(" bytes        :", t.n_bytes)
print(" split fields :", split_fields)

print()
print("STANDALONE PLE VERIFIED")
