"""Read-only inventory and compatibility gate for the owner's Qwen3.8 GGUF variants.

The eight model families come from data/personal_models.json. This utility never
copies GGUF weights, builds native packs, starts CUDA, or modifies E:/R:.

Examples (for a future inspection session, not required during source development):
  python tools/personal_models.py --list
  python tools/personal_models.py --check --json
  python tools/personal_models.py --check --path-prefix /mnt/drive-e/ai
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PureWindowsPath

try:
    from .model_compat import inspect as inspect_gguf
except ImportError:  # directly executable tools/personal_models.py
    from model_compat import inspect as inspect_gguf

CATALOG = Path(__file__).resolve().parent.parent / 'data' / 'personal_models.json'
FILENAME = re.compile(r'^[^\\/:*?"<>|]+$')


def load_catalog(path: Path = CATALOG) -> dict:
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema_version') != 1 or not isinstance(data.get('models'), list):
        raise ValueError('unsupported personal model inventory version')
    names = set()
    for m in data['models']:
        if not isinstance(m, dict) or not all(k in m for k in ('id', 'directory', 'shard_stem', 'shards', 'name_quantization', 'ple_policy')):
            raise ValueError('invalid personal model entry')
        if not FILENAME.fullmatch(m['id']) or not FILENAME.fullmatch(m['shard_stem']) or m['id'] in names:
            raise ValueError('unsafe or duplicate personal model identifier')
        names.add(m['id'])
        if type(m['shards']) is not int or not 1 <= m['shards'] <= 99999:
            raise ValueError('invalid GGUF shard count')
        path = PureWindowsPath(m['directory'])
        if not path.is_absolute() or path.drive.upper() != 'E:' or '..' in path.parts:
            raise ValueError('unexpected personal model directory')
        if m.get('mmproj') is not None and not FILENAME.fullmatch(m['mmproj']):
            raise ValueError('unsafe mmproj filename')
        if m['ple_policy'] == 'native_q8_only' and m['name_quantization'] != 'Q8_0':
            raise ValueError('native Q8 n-gram policy used with non-Q8 model')
    return data


def local_path(windows: str, prefix: Path | None = None) -> Path:
    source = PureWindowsPath(windows)
    if not source.is_absolute() or source.drive.upper() != 'E:' or '..' in source.parts:
        raise ValueError('expected an absolute E: path, without traversal')
    if prefix is None:
        # On Windows Path('E:\\ai...') addresses the real volume. On Linux
        # scanning must be explicitly mapped (never pretend the path exists).
        if sys.platform != 'win32':
            raise ValueError('a --path-prefix mapping is required outside Windows')
        return Path(str(source))
    pieces = source.parts[1:]
    if len(pieces) < 1 or pieces[0].lower() != 'ai':
        raise ValueError('only E:\\ai paths can be mapped')
    return prefix.joinpath(*pieces[1:])


def paths_for(model: dict, prefix: Path | None = None) -> list[Path]:
    directory = local_path(model['directory'], prefix)
    n = model['shards']
    return [directory / (f"{model['shard_stem']}-{i:05d}-of-{n:05d}.gguf")
            for i in range(1, n + 1)] if n > 1 else [directory / (model['shard_stem'] + '.gguf')]


def check(model: dict, prefix: Path | None = None, *, headers: bool = True) -> dict:
    """Return evidence, never a promise that the CUDA/CPU implementation works."""
    result = {'id': model['id'], 'quantization_label': model['name_quantization'],
              'model_directory': model['directory'], 'expected_shards': model['shards'],
              'source_only': True, 'engine_runtime_verified': False}
    try:
        files = paths_for(model, prefix)
        missing = [i + 1 for i, path in enumerate(files) if not path.is_file()]
        result['shards_found'] = len(files) - len(missing)
        result['missing_shards'] = missing
        if missing:
            result['status'] = 'missing_shards'
            return result
        if not headers:
            result['status'] = 'names_present_only'
            return result
        details = inspect_gguf(files)
        result['architecture'] = details['architecture']
        result['expert_quantizations'] = details['quantization_by_role'].get('routed_experts', {})
        result['ple_table'] = details['ple_table']
        result['warnings'] = details['warnings']
        result['projector_present'] = (local_path(model['directory'], prefix) / model['mmproj']).is_file() if model.get('mmproj') else None
        if details['architecture'] != 'qwen4exp':
            result['status'] = 'architecture_mismatch'
        elif model['ple_policy'] == 'native_q8_only' and (
            details['ple_table']['type'] != 'Q8_0' or not details['ple_table']['native_reader_type']
        ):
            result['status'] = 'native_q8_ple_unavailable'
        else:
            result['status'] = 'headers_compatible_runtime_unverified'
    except (OSError, ValueError, KeyError, IndexError, EOFError) as e:
        result['status'] = 'invalid_headers_or_paths'
        result['error'] = str(e)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument('--list', action='store_true', help='show all known variants without accessing weights')
    actions.add_argument('--check', action='store_true', help='inspect local GGUF shard headers only')
    parser.add_argument('--model', action='append', help='restrict to a model id; repeatable')
    parser.add_argument('--path-prefix', type=Path, help='map E:\\ai to another directory for read-only inspection')
    parser.add_argument('--names-only', action='store_true', help='check existence without opening GGUF headers')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args(argv)
    try:
        catalog = load_catalog()
        models = catalog['models']
        requested = set(args.model or [])
        unknown = requested - {m['id'] for m in models}
        if unknown:
            raise ValueError('unknown model ids: ' + ', '.join(sorted(unknown)))
        selected = [m for m in models if not requested or m['id'] in requested]
        results = ([{'id': m['id'], 'quantization_label': m['name_quantization'],
                     'model_directory': m['directory'], 'expected_shards': m['shards'],
                     'first_shard': str(PureWindowsPath(m['directory']) / f"{m['shard_stem']}-00001-of-{m['shards']:05d}.gguf"),
                     'mmproj': m.get('mmproj')} for m in selected]
                   if args.list else [check(m, args.path_prefix, headers=not args.names_only) for m in selected])
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(2, f'Personal model inventory rejected: {exc}\n')
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        for row in results:
            print(f"{row['id']}: {row['quantization_label']} / {row['expected_shards']} shards / "
                  f"{row.get('status', 'catalogued, not validated')}")
    return 0 if args.list or all(r['status'] in ('names_present_only', 'headers_compatible_runtime_unverified') for r in results) else 2


if __name__ == '__main__':
    raise SystemExit(main())
