from __future__ import annotations
import argparse, json, os, sys
from pathlib import Path, PureWindowsPath

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'data' / 'personal_models.json'
sys.path.insert(0, str(ROOT / 'tools'))
from gguf_reader import GGUFFile  # noqa: E402


def local_path(win: str, prefix: Path | None) -> Path:
    p = PureWindowsPath(win)
    if prefix is None:
        return Path(str(p))
    parts = list(p.parts)
    if parts and parts[0].endswith('\\'):
        parts = parts[1:]
    return prefix.joinpath(*parts)


def load_model(mid: str):
    cat=json.loads(CATALOG.read_text(encoding='utf-8'))
    for m in cat['models']:
        if m['id']==mid or mid in m.get('aliases',[]): return m
    raise SystemExit(f'unknown model id: {mid}')


def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--model', required=True)
    ap.add_argument('--path-prefix', type=Path)
    ap.add_argument('--json', action='store_true')
    a=ap.parse_args()
    m=load_model(a.model)
    d=local_path(m['directory'], a.path_prefix)
    expected=[d / name for name in m['files']]
    # Future/downloaded variants may not have a stable publisher filename yet.
    # Resolve exactly one completed GGUF by catalog model_glob, but never a .part/downloading_ file.
    glob_match=None
    if any(not p.is_file() for p in expected) and m.get('model_glob') and d.is_dir():
        matches=sorted(p for p in d.glob(str(m['model_glob'])) if p.is_file() and not p.name.endswith('.part') and not p.name.startswith('downloading_'))
        if len(matches)==1 and len(expected)==1:
            expected=[matches[0]]
            glob_match=matches[0].name
    missing=[p for p in expected if not p.is_file()]
    parts=[]
    if d.is_dir():
        parts=sorted([p.name for p in d.iterdir() if p.is_file() and (p.name.endswith('.part') or p.name.startswith('downloading_'))])
    result={'id':m['id'],'arch_expected':m['arch'],'directory':str(d),'expected_files':[p.name for p in expected],
            'missing':[p.name for p in missing],'partial_files':parts,'state':'missing','glob_match':glob_match}
    if missing:
        result['state']='downloading' if parts else 'missing'
    else:
        first=expected[0]
        try:
            g=GGUFFile(first)
            arch=g.metadata.get('general.architecture')
            result['arch_found']=arch
            if arch != m['arch']:
                result['state']='architecture_mismatch'
            else:
                result['state']='ready'
                if m['arch']=='qwen35moe':
                    types=sorted({t.type_name for t in g.tensors if '.ffn_' in t.name or '.mlp.experts.' in t.name})
                    result['expert_tensor_types']=types
        except Exception as e:
            result['state']='invalid_gguf'
            result['error']=str(e)
    if a.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"{m['id']}: {result['state']}")
        if missing: print('missing: ' + ', '.join(p.name for p in missing))
        if parts: print('partial: ' + ', '.join(parts))
        if result.get('arch_found'): print('arch: ' + str(result['arch_found']))
    return 0 if result['state']=='ready' else 2

if __name__=='__main__':
    raise SystemExit(main())
