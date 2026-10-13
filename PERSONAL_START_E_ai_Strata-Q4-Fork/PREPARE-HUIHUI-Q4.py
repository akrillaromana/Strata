#!/usr/bin/env python3
"""Safe GGUF-metadata audit and dedicated native-pack build for Huihui UD-Q4_K_XL.

Does not modify GGUF shards, Unsloth packs, or Strata binaries.
"""
import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SHARDS = [f'Qwen3.8-Flash-Next-UD-Q4_K_XL-{i:05d}-of-00004.gguf' for i in range(1,5)]
TYPES = {0:('B',1),1:('b',1),2:('H',2),3:('h',2),4:('I',4),5:('i',4),6:('f',4),7:('?',1),10:('Q',8),11:('q',8),12:('d',8)}
PACK_SENTINEL = 'HUIHUI-PACK-PROVENANCE.json'

class FormatError(RuntimeError):
    pass

class Reader:
    def __init__(self, data):
        self.data = data
        self.n = len(data)
        self.at = 0
    def take(self, n):
        if n < 0 or self.at+n > self.n:
            raise FormatError(f'truncated GGUF header at offset {self.at}, need {n} more bytes')
        a=self.data[self.at:self.at+n]
        self.at+=n
        return a
    def u32(self): return struct.unpack('<I', self.take(4))[0]
    def u64(self): return struct.unpack('<Q', self.take(8))[0]
    def string(self):
        n=self.u64()
        if n > 20_000_000: raise FormatError(f'invalid GGUF string size {n}')
        return self.take(n).decode('utf-8','replace')
    def item(self,typ):
        if typ==8: return self.string()
        if typ==9:
            elem=self.u32(); count=self.u64()
            if count>20_000_000: raise FormatError(f'oversized GGUF array {count}')
            if elem in TYPES:
                fmt,sz=TYPES[elem]
                raw=self.take(count*sz)
                # Return only a summary for large arrays. Geometry keys are scalars.
                if count>32:
                    return {'array_type':elem,'count':count,'sha256':hashlib.sha256(raw).hexdigest()}
                return list(struct.unpack('<'+fmt*count,raw))
            if elem==8:
                if count>32:
                    digest=hashlib.sha256()
                    for _ in range(count):
                        n=self.u64()
                        if n>20_000_000:raise FormatError('invalid GGUF array string')
                        raw=self.take(n)
                        digest.update(struct.pack('<Q',n));digest.update(raw)
                    return {'array_type':elem,'count':count,'sha256':digest.hexdigest()}
                return [self.string() for _ in range(count)]
            if elem==9:
                if count>10000:raise FormatError('too many nested GGUF array items')
                return [self.item(elem) for _ in range(count)]
            raise FormatError(f'unknown GGUF array type {elem}')
        if typ not in TYPES: raise FormatError(f'unknown GGUF metadata type {typ}')
        fmt,_=TYPES[typ]
        return struct.unpack('<'+fmt,self.take(TYPES[typ][1]))[0]

def metadata_from_first(path):
    # A first shard is ~11MB. Read at most 64MB, never touch the giant PLE shard.
    with path.open('rb') as f:
        head=f.read(64*1024*1024)
    r=Reader(head)
    if r.take(4)!=b'GGUF': raise FormatError(f'{path}: magic is not GGUF')
    version=r.u32(); nt=r.u64(); nm=r.u64()
    if version not in (2,3): raise FormatError(f'unsupported GGUF version: {version}')
    if nm>100000: raise FormatError(f'unreasonable metadata count: {nm}')
    md={}
    for _ in range(nm):
        key=r.string();typ=r.u32()
        if key in md: raise FormatError(f'duplicate GGUF metadata key: {key}')
        md[key]=r.item(typ)
    return {'version':version,'tensor_count':nt,'metadata_count':nm,'kv':md}

def sha256_file(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for part in iter(lambda:f.read(1024*1024),b''):
            h.update(part)
    return h.hexdigest()

def shards_at(folder):
    out=[]
    for name in SHARDS:
        p=folder/name
        if not p.is_file(): raise FormatError(f'missing shard: {p}')
        if p.stat().st_size<1024: raise FormatError(f'shard too small: {p}')
        out.append(p)
    return out

def validate(args):
    huihui=Path(args.models);base=Path(args.original)
    hs=shards_at(huihui)
    hmeta=metadata_from_first(hs[0]);hm=hmeta['kv']
    bm={}
    print('HUIHUI first shard:',hs[0])
    print('HUIHUI first shard size:',hs[0].stat().st_size)
    print('HUIHUI first shard SHA256:',sha256_file(hs[0]))
    print('HUIHUI metadata count:',len(hm),'tensor count:',hmeta['tensor_count'])
    for k in ('general.architecture','qwen4exp.block_count','split.count','split.no','split.tensors.count'):
        print(f'  {k}: {hm.get(k,"<ABSENT>")}')
    if (base/SHARDS[0]).is_file():
        bm=metadata_from_first(base/SHARDS[0])['kv']
        print('ORIGINAL first shard:',base/SHARDS[0])
        for k in ('general.architecture','qwen4exp.block_count','split.count'):
            print(f'  original {k}: {bm.get(k,"<ABSENT>")}')
    else:
        print('NOTE: original GGUF first shard missing; geometry parity cannot be compared:',base/SHARDS[0])
    print('Shard sizes (GiB):',*[f'{p.stat().st_size/2**30:.3f}' for p in hs])
    problems=[]
    if hm.get('general.architecture')!='qwen4exp':
        problems.append(f'general.architecture is {hm.get("general.architecture")!r}, expected qwen4exp')
    if not isinstance(hm.get('qwen4exp.block_count'),int) or hm['qwen4exp.block_count']<=0:
        problems.append('qwen4exp.block_count is absent/invalid in Huihui shard 1; repacking will NOT fix missing GGUF metadata')
    if hm.get('split.count') not in (None,4):
        problems.append(f'split.count={hm["split.count"]!r}, expected 4')
    if hm.get('split.no') not in (None,0):
        problems.append(f'split.no={hm["split.no"]!r}, expected 0')
    if bm:
        if bm.get('general.architecture')!=hm.get('general.architecture'):
            problems.append('architecture differs from original')
        # Compare geometry keys only: abliterated model should preserve architecture shape.
        for key,basevalue in sorted(bm.items()):
            if key.startswith('qwen4exp.') and (key not in hm or hm[key]!=basevalue):
                problems.append('geometry mismatch: '+key+f' original={str(basevalue)[:100]!r} Huihui={str(hm.get(key,"<ABSENT>"))[:100]!r}')
    if problems:
        print('\nCHECK: BLOCKED. Native GGUF metadata is not confirmed compatible:')
        for i,p in enumerate(problems,1): print(f'  {i}. {p}')
        print('No files changed. Do NOT reuse the original Unsloth pack.')
        raise FormatError('GGUF metadata check failed')
    print('\nCHECK: GGUF geometry metadata compatible (first shard).')
    return hs

def stamp_for(shards):
    return {'schema':1,'variant':'huihui-ai/Huihui-Qwen3.8-Flash-Next-abliterated-GGUF/UD-Q4_K_XL',
            'first_shard_sha256':sha256_file(shards[0]),
            'shards':[{'name':p.name,'bytes':p.stat().st_size} for p in shards]}

def check_pack(args, shards):
    out=Path(args.output)
    sent=out/PACK_SENTINEL
    if not sent.is_file():raise FormatError(f'pack provenance marker missing: {sent}; run --build first')
    got=json.loads(sent.read_text(encoding='utf-8'))
    expected=stamp_for(shards)
    if {k:got.get(k) for k in expected}!={k:expected[k] for k in expected}:
        raise FormatError('Huihui pack provenance differs from the current four GGUF shards; do not start')
    for name in ('index.txt','dense.bin','native_experts.txt'):
        if not (out/name).is_file() or (out/name).stat().st_size==0:
            raise FormatError(f'incomplete Huihui native pack: {out/name}')
    if not (out/'tokenizer'/'vocab.json').is_file():
        raise FormatError(f'missing tokenizer in Huihui pack: {out}/tokenizer/vocab.json')
    print('CHECK PACK: provenance and required pack files OK:',out)

def build(args,shards):
    root=Path(args.root)
    tool=root/'tools'/'iq_pack.py'
    if not tool.is_file():raise FormatError(f'No pack builder: {tool}')
    out=Path(args.output)
    if out.exists():
        check_pack(args,shards)
        print('Pack already complete. No rebuild done.')
        return
    staging=out.with_name(out.name+'.building')
    if staging.exists():raise FormatError(f'previous staging directory exists; inspect before deleting: {staging}')
    out.parent.mkdir(parents=True,exist_ok=True)
    cmd=[sys.executable,str(tool),'--gguf',str(shards[0]),'--out',str(staging),'--compat-bf16']
    print('\nBuilding dedicated Huihui pack (original Unsloth pack untouched):')
    print(' '.join(cmd),flush=True)
    try:
        subprocess.run(cmd,check=True,cwd=str(root))
        for name in ('index.txt','dense.bin','native_experts.txt'):
            if not (staging/name).is_file() or (staging/name).stat().st_size==0:
                raise FormatError(f'pack build incomplete: {staging/name}')
        if not (staging/'tokenizer'/'vocab.json').is_file():
            raise FormatError('pack tokenizer not exported')
        stamp=stamp_for(shards)
        stamp['built_at']=datetime.now().isoformat(timespec='seconds')
        (staging/PACK_SENTINEL).write_text(json.dumps(stamp,indent=2)+'\n',encoding='utf-8')
        staging.rename(out)
    except Exception:
        print(f'Build aborted. If staging exists, inspect: {staging}')
        raise
    check_pack(args,shards)
    print('PACK READY:',out)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',default=r'E:\ai\Strata-Q4-Fork')
    ap.add_argument('--models',default=r'E:\ai\models\huihui-ai\Huihui-Qwen3.8-Flash-Next-abliterated-GGUF')
    ap.add_argument('--original',default=r'E:\ai\models\unsloth\Qwen3.8-Flash-Next-GGUF')
    ap.add_argument('--output',default=r'E:\ai\Strata-data\packs\huihui-ud-q4_k_xl')
    choice=ap.add_mutually_exclusive_group()
    choice.add_argument('--build',action='store_true')
    choice.add_argument('--check-pack',action='store_true')
    args=ap.parse_args()
    shards=validate(args)
    if args.build:build(args,shards)
    elif args.check_pack:check_pack(args,shards)
    return 0

if __name__=='__main__':
    try:
        raise SystemExit(main())
    except Exception as e:
        print('ERROR:',str(e),file=sys.stderr)
        raise SystemExit(1)
