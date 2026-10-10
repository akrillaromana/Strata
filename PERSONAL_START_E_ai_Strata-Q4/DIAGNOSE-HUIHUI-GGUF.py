#!/usr/bin/env python3
"""Read header metadata of ALL FOUR GGUF shards, with no heavy tensor reads or writes."""
from pathlib import Path
import importlib.util
import json
import os
import sys
import hashlib

SCRIPT = Path(__file__).resolve().parent / 'PREPARE-HUIHUI-Q4.py'
spec = importlib.util.spec_from_file_location('prep', SCRIPT)
prep = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prep)
ROOT = Path(r'E:\ai\Strata-Q4')
MODEL = Path(r'E:\ai\models\huihui-ai\Huihui-Qwen3.8-Flash-Next-abliterated-GGUF')
RAM = Path(r'R:\q4-model')


def report(folder, mandatory):
    print(f'===== {folder} =====')
    seen = []
    for index, name in enumerate(prep.SHARDS, start=1):
        path = folder/name
        if not path.exists():
            print(f'Shard {index}: MISSING: {path}')
            if mandatory: raise FileNotFoundError(path)
            return
        md = prep.metadata_from_first(path)
        kv = md['kv']
        seen.append(kv)
        is_link = path.is_symlink()
        print(f'#{index} size={path.stat().st_size} tensor_count={md["tensor_count"]} '
              f'metadata_count={md["metadata_count"]} link={is_link}')
        if is_link:
            print('      target=',str(path.resolve()))
        for key in ('general.architecture','qwen4exp.block_count','split.count','split.no','split.tensors.count'):
            print(f'      {key}: {kv.get(key,"<ABSENT>")}')
    if seen:
        print('Shard(s) with qwen4exp.block_count:', [i for i,x in enumerate(seen,1) if 'qwen4exp.block_count' in x])
    print()


def main():
    print('Huihui GGUF metadata diagnosis (non-destructive)')
    report(MODEL, True)
    if RAM.exists():report(RAM, False)
    for p in (ROOT/'engine'/'BUILD.json', ROOT/'BUILD.json'):
        if p.is_file():print('Engine BUILD:',p,'\n',p.read_text(encoding='utf-8-sig')[:1000])
    c=ROOT/'strata-huihui-ud-q4_k_xl-RAM.json'
    if c.is_file():
        obj=json.loads(c.read_text(encoding='utf-8-sig'))
        print('Config --native:',obj.get('args',[])[obj.get('args',[]).index('--native')+1] if '--native' in obj.get('args',[]) else '(missing)')
        print('Config host:',obj.get('host'))
        print('Config --native-dense-gguf:', '--native-dense-gguf' in obj.get('args',[]))
    print('SUMMARY: A key existing in shard1 does NOT prove the engine read shard1.')
    print('No files changed.')
    return 0

if __name__=='__main__':
    try: raise SystemExit(main())
    except Exception as e:
        print('ERROR:',repr(e),file=sys.stderr)
        raise SystemExit(1)
