import importlib.util
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE=Path(__file__).resolve().parent
SCRIPT=HERE/'PREPARE-HUIHUI-Q4.py'
NAMES=[f'Qwen3.8-Flash-Next-UD-Q4_K_XL-{i:05d}-of-00004.gguf' for i in range(1,5)]

def str_item(x):
    b=x.encode('utf-8'); return struct.pack('<Q',len(b))+b

def meta_item(k,t,v):
    if t==8: data=str_item(v)
    elif t==4: data=struct.pack('<I',v)
    elif t==9:
        data=struct.pack('<IQ',8,len(v)) + b''.join(str_item(q) for q in v)
    else: raise AssertionError(t)
    return str_item(k)+struct.pack('<I',t)+data

def gguf_file(path, *, block_count=48, architecture='qwen4exp', fake_tokenizer=False):
    kv=[('general.architecture',8,architecture),('split.count',4,4),('split.no',4,0)]
    if block_count is not None:kv.append(('qwen4exp.block_count',4,block_count))
    kv.append(('qwen4exp.embedding_length',4,2560))
    if fake_tokenizer:kv.append(('tokenizer.ggml.tokens',9,[f'tok-{i}' for i in range(25000)]))
    header=b'GGUF'+struct.pack('<IQQ',3,0,len(kv))+b''.join(meta_item(*item) for item in kv)
    path.write_bytes(header+b'\0'*2048)

def run(root,models,original,output,extra=()):
    return subprocess.run([sys.executable,str(SCRIPT),'--root',str(root), '--models',str(models), '--original',str(original),'--output',str(output),*extra],capture_output=True,text=True)

def main():
    with tempfile.TemporaryDirectory(prefix='strata-huihui-validation-') as d:
        base=Path(d)
        root=base/'Strata-Q4'
        models=base/'Huihui'
        original=base/'Unsloth'
        out=base/'Strata-data'/'packs'/'huihui-ud-q4_k_xl'
        (root/'tools').mkdir(parents=True)
        models.mkdir();original.mkdir()
        for f in NAMES:
            (models/f).write_bytes(b'MODEL\0'*300)
            (original/f).write_bytes(b'ORIGINAL\0'*300)
        gguf_file(models/NAMES[0],fake_tokenizer=True)
        gguf_file(original/NAMES[0],fake_tokenizer=True)

        p=run(root,models,original,out)
        assert p.returncode==0,(p.stdout,p.stderr)
        assert 'qwen4exp.block_count: 48' in p.stdout
        print('PASS: metadata probe on synthetic 25,000-token GGUF')

        p=run(root,models,original,out,['--check-pack'])
        assert p.returncode!=0 and 'pack provenance marker missing' in p.stderr,(p.stdout,p.stderr)
        print('PASS: refuses to launch with missing dedicated pack')

        gguf_file(models/NAMES[0],block_count=None)
        p=run(root,models,original,out)
        assert p.returncode!=0 and 'qwen4exp.block_count is absent' in p.stdout,(p.stdout,p.stderr)
        assert not out.exists()
        print('PASS: absent block_count aborts before pack build')
        gguf_file(models/NAMES[0],fake_tokenizer=True)

        gguf_file(models/NAMES[0],block_count=47)
        p=run(root,models,original,out)
        assert p.returncode!=0 and 'geometry mismatch: qwen4exp.block_count' in p.stdout
        print('PASS: different geometry aborts')
        gguf_file(models/NAMES[0],fake_tokenizer=True)

        (root/'tools'/'iq_pack.py').write_text('''from pathlib import Path
import sys
p=Path(sys.argv[sys.argv.index('--out')+1])
p.mkdir(parents=True)
for name in ('index.txt','dense.bin','native_experts.txt'):
    (p/name).write_bytes(b'test')
(p/'tokenizer').mkdir()
(p/'tokenizer'/'vocab.json').write_text('{}')
''')
        p=run(root,models,original,out,['--build'])
        assert p.returncode==0,(p.stdout,p.stderr)
        assert (out/'HUIHUI-PACK-PROVENANCE.json').is_file()
        assert (out/'dense.bin').is_file()
        print('PASS: creates only a dedicated pack through test pack builder')

        p=run(root,models,original,out,['--check-pack'])
        assert p.returncode==0,(p.stdout,p.stderr)
        print('PASS: pack provenance validated')

        p=run(root,models,original,out,['--build'])
        assert p.returncode==0 and 'Pack already complete' in p.stdout,(p.stdout,p.stderr)
        print('PASS: repeated build does not overwrite existing valid pack')

        with (models/NAMES[2]).open('ab') as f:f.write(b'altered')
        p=run(root,models,original,out,['--check-pack'])
        assert p.returncode!=0 and 'provenance differs' in p.stderr,(p.stdout,p.stderr)
        print('PASS: shard change invalidates pack provenance')

        assert not (root/'packs').exists()
        print('PASS: Unsloth pack and original model left untouched')

if __name__=='__main__':main()
