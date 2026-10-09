from __future__ import annotations

import sys
from pathlib import Path
import gguf


META = Path(sys.argv[1])
PLE_SOURCE = Path(sys.argv[2])
OUTPUT = Path(sys.argv[3])

TENSOR_NAME = "per_layer_token_embd.weight"


def value(reader, key):
    f = reader.get_field(key)
    return None if f is None else f.contents()


print("META       :", META)
print("PLE SOURCE :", PLE_SOURCE)
print("OUTPUT     :", OUTPUT)
print()


meta = gguf.GGUFReader(META, "r")
src  = gguf.GGUFReader(PLE_SOURCE, "r")


# ------------------------------------------------------------
# Architecture
# ------------------------------------------------------------

arch = value(
    meta,
    gguf.Keys.General.ARCHITECTURE
)

if arch is None:
    raise RuntimeError(
        "general.architecture missing in shard1"
    )

if isinstance(arch, bytes):
    arch = arch.decode("utf-8")

arch = str(arch)

print("architecture:", arch)


# ------------------------------------------------------------
# Locate PLE
# ------------------------------------------------------------

ple = None

for t in src.tensors:
    if t.name == TENSOR_NAME:
        ple = t
        break

if ple is None:
    raise RuntimeError(
        f"{TENSOR_NAME} not found"
    )


print()
print("PLE:")
print(" name    :", ple.name)
print(" type    :", ple.tensor_type)
print(" bytes   :", ple.n_bytes)
print(
    " GiB     :",
    round(ple.n_bytes / (1024**3), 3)
)
print(" shape   :", ple.shape.tolist())


# ------------------------------------------------------------
# New standalone GGUF
# ------------------------------------------------------------

OUTPUT.parent.mkdir(
    parents=True,
    exist_ok=True
)

if OUTPUT.exists():
    OUTPUT.unlink()


writer = gguf.GGUFWriter(
    OUTPUT,
    arch=arch,
    endianess=meta.endianess
)

writer.data_alignment = src.alignment


# ------------------------------------------------------------
# Copy metadata from architecture shard.
#
# Exclude:
# - general.architecture: writer constructor added it
# - general.alignment: writer handles alignment
# - split.*: standalone file MUST NOT belong to Q4 split
# ------------------------------------------------------------

skip_exact = {
    str(gguf.Keys.General.ARCHITECTURE),
    str(gguf.Keys.General.ALIGNMENT),
    "general.architecture",
    "general.alignment",
}

copied = []
skipped_split = []
failed_optional = []


for field in meta.fields.values():

    name = field.name

    if name in skip_exact:
        continue

    if name.startswith("split."):
        skipped_split.append(name)
        continue

    data = field.contents()
    types = field.types

    if not types:
        continue

    vtype = types[0]

    try:

        if vtype == gguf.GGUFValueType.ARRAY:

            # Current gguf-py has add_array().
            if hasattr(writer, "add_array"):
                writer.add_array(
                    name,
                    data
                )
            else:
                # Fallback for another gguf-py API revision.
                writer.add_key_value(
                    name,
                    data,
                    vtype
                )

        else:

            writer.add_key_value(
                name,
                data,
                vtype
            )

        copied.append(name)

    except Exception as e:
        failed_optional.append(
            (name, repr(e))
        )


print()
print("METADATA:")
print(" copied:", len(copied))
print(
    " qwen4exp fields:",
    len([
        x for x in copied
        if x.startswith("qwen4exp.")
    ])
)

for k in copied:
    if k.startswith("qwen4exp."):
        print(" ", k)


if failed_optional:
    print()
    print("FIELDS THAT COULD NOT BE COPIED:")

    for name, err in failed_optional:
        print(" ", name, "->", err)


# qwen4exp.block_count is already known to be mandatory.
if "qwen4exp.block_count" not in copied:
    raise RuntimeError(
        "qwen4exp.block_count was NOT copied"
    )


# ------------------------------------------------------------
# Add raw IQ4_NL PLE tensor
# ------------------------------------------------------------

writer.add_tensor(
    ple.name,
    ple.data,
    raw_dtype=ple.tensor_type,
    tensor_endianess=src.endianess
)


writer.write_header_to_file()
writer.write_kv_data_to_file()
writer.write_tensors_to_file(
    progress=True
)
writer.close()


print()
print("FILE WRITTEN")
print(
    " size GiB:",
    round(
        OUTPUT.stat().st_size / (1024**3),
        3
    )
)


# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

check = gguf.GGUFReader(
    OUTPUT,
    "r"
)


print()
print("VERIFY:")

print(
    " architecture:",
    value(
        check,
        gguf.Keys.General.ARCHITECTURE
    )
)

block_count = check.get_field(
    "qwen4exp.block_count"
)

print(
    " qwen4exp.block_count:",
    None if block_count is None
    else block_count.contents()
)


if block_count is None:
    raise RuntimeError(
        "qwen4exp.block_count missing after write"
    )


split_fields = [
    f.name
    for f in check.fields.values()
    if f.name.startswith("split.")
]

print(
    " split fields:",
    split_fields
)

if split_fields:
    raise RuntimeError(
        "split metadata survived"
    )


if len(check.tensors) != 1:
    raise RuntimeError(
        f"expected 1 tensor, got {len(check.tensors)}"
    )


t = check.tensors[0]

print(" tensor :", t.name)
print(" type   :", t.tensor_type)
print(" bytes  :", t.n_bytes)


if t.name != TENSOR_NAME:
    raise RuntimeError(
        "wrong tensor"
    )

if t.tensor_type != ple.tensor_type:
    raise RuntimeError(
        "quantization changed"
    )

if t.n_bytes != ple.n_bytes:
    raise RuntimeError(
        "tensor byte size changed"
    )


print()
print("FULL-METADATA STANDALONE PLE VERIFIED")
