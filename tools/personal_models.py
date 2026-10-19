"""Read-only inventory and compatibility gate for the owner's Strata-supported local models.

Schema v2 covers both Strata engine families:
  * qwen4exp  - Qwen3.8-Flash-Next and compatible fine-tunes/quants;
  * qwen35moe - Qwen3.6-35B-A3B.
Models still downloading are catalogued by their final GGUF names and reported as
``downloading`` until those final files exist.  This tool never modifies E:/R:.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path, PureWindowsPath
try:
    from .model_compat import inspect as inspect_qwen4exp
    from .gguf_reader import GGUFFile
except ImportError:
    from model_compat import inspect as inspect_qwen4exp
    from gguf_reader import GGUFFile

CATALOG=Path(__file__).resolve().parent.parent/'data'/'personal_models.json'
SAFE_ID=re.compile(r'^[A-Za-z0-9._-]+$')
SAFE_FILE=re.compile(r'^[^\\/:*?"<>|]+$')


def load_catalog(path: Path=CATALOG)->dict:
    d=json.loads(path.read_text(encoding='utf-8'))
    if d.get('schema_version') not in (1,2) or not isinstance(d.get('models'),list):
        raise ValueError('unsupported personal model inventory version')
    seen=set()
    for m in d['models']:
        if not isinstance(m,dict) or not all(k in m for k in ('id','directory')):
            raise ValueError('invalid personal model entry')
        if not SAFE_ID.fullmatch(str(m['id'])) or m['id'] in seen:
            raise ValueError('unsafe or duplicate personal model identifier')
        seen.add(m['id'])
        p=PureWindowsPath(m['directory'])
        if not p.is_absolute() or p.drive.upper()!='E:' or '..' in p.parts:
            raise ValueError('unexpected personal model directory')
        if d['schema_version']==2:
            if m.get('arch') not in ('qwen4exp','qwen35moe') or not isinstance(m.get('files'),list) or not m['files']:
                raise ValueError('invalid schema-v2 model entry')
            for f in m['files']:
                if not SAFE_FILE.fullmatch(str(f)): raise ValueError('unsafe model filename')
        else:
            if not all(k in m for k in ('shard_stem','shards','name_quantization','ple_policy')):
                raise ValueError('invalid schema-v1 model entry')
    return d


def local_path(windows: str,prefix:Path|None=None)->Path:
    source=PureWindowsPath(windows)
    if not source.is_absolute() or source.drive.upper()!='E:' or '..' in source.parts:
        raise ValueError('expected absolute E: path')
    if prefix is None:
        if sys.platform!='win32': raise ValueError('a --path-prefix mapping is required outside Windows')
        return Path(str(source))
    pieces=source.parts[1:]
    if not pieces or pieces[0].lower()!='ai': raise ValueError('only E:\\ai paths can be mapped')
    return prefix.joinpath(*pieces[1:])


def paths_for(m:dict,prefix:Path|None=None)->list[Path]:
    d=local_path(m['directory'],prefix)
    if 'files' in m: return [d/str(f) for f in m['files']]
    n=int(m['shards'])
    return [d/f"{m['shard_stem']}-{i:05d}-of-{n:05d}.gguf" for i in range(1,n+1)] if n>1 else [d/(m['shard_stem']+'.gguf')]


def check(m:dict,prefix:Path|None=None,headers:bool=True)->dict:
    files=paths_for(m,prefix)
    # If the publisher's final filename is not known yet, a catalog model_glob may
    # select exactly one completed GGUF after download. Never match partial files.
    glob_match=None
    if any(not p.is_file() for p in files) and m.get('model_glob') and len(files)==1:
        d=files[0].parent
        if d.is_dir():
            matches=sorted(p for p in d.glob(str(m['model_glob'])) if p.is_file() and not p.name.endswith('.part') and not p.name.startswith('downloading_'))
            if len(matches)==1:
                files=[matches[0]]; glob_match=matches[0].name
    result={'id':m['id'],'quantization_label':m.get('quantization',m.get('name_quantization')),
            'architecture_expected':m.get('arch','qwen4exp'),'model_directory':m['directory'],
            'expected_files':[p.name for p in files],'source_only':True,'engine_runtime_verified':False,'glob_match':glob_match}
    try:
        missing=[p for p in files if not p.is_file()]
        result['files_found']=len(files)-len(missing); result['missing_files']=[p.name for p in missing]
        if missing:
            d=files[0].parent
            parts=[] if not d.is_dir() else sorted(p.name for p in d.iterdir() if p.is_file() and (p.name.endswith('.part') or p.name.startswith('downloading_')))
            result['partial_files']=parts
            result['status']='downloading' if parts else 'missing_files'
            return result
        if not headers:
            result['status']='names_present_only'; return result
        expected=result['architecture_expected']
        if expected=='qwen4exp':
            details=inspect_qwen4exp(files)
            result['architecture']=details['architecture']
            result['expert_quantizations']=details['quantization_by_role'].get('routed_experts',{})
            result['ple_table']=details['ple_table']; result['warnings']=details['warnings']
            result['status']='headers_compatible_runtime_unverified' if details['architecture']=='qwen4exp' else 'architecture_mismatch'
        else:
            g=GGUFFile(files[0]); arch=g.metadata.get('general.architecture'); result['architecture']=arch
            result['expert_tensor_types']=sorted({t.type_name for t in g.tensors if '.ffn_' in t.name or '.mlp.experts.' in t.name})
            result['status']='headers_compatible_runtime_unverified' if arch=='qwen35moe' else 'architecture_mismatch'
        if m.get('mmproj'):
            result['projector_present']=(local_path(m['directory'],prefix)/m['mmproj']).is_file()
    except (OSError,ValueError,KeyError,IndexError,EOFError) as e:
        result['status']='invalid_headers_or_paths'; result['error']=str(e)
    return result


def main(argv=None)->int:
    ap=argparse.ArgumentParser(description=__doc__)
    g=ap.add_mutually_exclusive_group(required=True); g.add_argument('--list',action='store_true'); g.add_argument('--check',action='store_true')
    ap.add_argument('--model',action='append'); ap.add_argument('--path-prefix',type=Path); ap.add_argument('--names-only',action='store_true'); ap.add_argument('--json',action='store_true')
    a=ap.parse_args(argv)
    try:
        cat=load_catalog(); req=set(a.model or [])
        alias_to_id={}
        for m in cat['models']:
            alias_to_id[m['id']]=m['id']
            for alias in m.get('aliases',[]): alias_to_id[str(alias)]=m['id']
        unknown=req-set(alias_to_id)
        if unknown: raise ValueError('unknown model ids: '+', '.join(sorted(unknown)))
        canonical={alias_to_id[x] for x in req}
        models=[m for m in cat['models'] if not canonical or m['id'] in canonical]
        if a.list:
            rows=[{'id':m['id'],'architecture':m.get('arch','qwen4exp'),'quantization_label':m.get('quantization',m.get('name_quantization')),
                   'model_directory':m['directory'],'expected_files':[p.name for p in paths_for(m,a.path_prefix) if a.path_prefix is not None] if a.path_prefix else list(m.get('files',[])),
                   'state':m.get('state','unknown'),'config':m.get('config')} for m in models]
        else: rows=[check(m,a.path_prefix,headers=not a.names_only) for m in models]
    except (OSError,ValueError,KeyError) as e: ap.exit(2,f'Personal model inventory rejected: {e}\n')
    if a.json: print(json.dumps(rows,ensure_ascii=False,indent=2))
    else:
        for r in rows: print(f"{r['id']}: {r['quantization_label']} / {r.get('architecture',r.get('architecture_expected'))} / {r.get('status',r.get('state','catalogued'))}")
    good={'names_present_only','headers_compatible_runtime_unverified'}
    return 0 if a.list or all(r.get('status') in good for r in rows) else 2
if __name__=='__main__': raise SystemExit(main())
