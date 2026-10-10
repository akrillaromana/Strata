"""Offline, sparse synthetic GGUF checks for the owner's native Q8_0 n-gram path."""
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import q8_ple_preflight as preflight


def text(s):
    b = s.encode()
    return struct.pack('<Q', len(b)) + b


def gguf(path, *, kind=8, shape=(160, preflight.PLE_ROWS), extra=None, sparse=False, truncated=False):
    ts = [('per_layer_token_embd.weight', shape, kind)] if kind is not None else []
    if extra:
        ts.extend(extra)
    header = bytearray(b'GGUF' + struct.pack('<IQQ', 3, len(ts), 0))
    offset = 0
    for name, dims, dtype in ts:
        header += text(name) + struct.pack('<I',len(dims)) + struct.pack('<'+'Q'*len(dims), *dims)
        header += struct.pack('<IQ',dtype,offset)
        if dtype == 8: offset += dims[0]*dims[1]//32*34
        else: offset += dims[0]*dims[1]//32*18
    header += bytes(-len(header)%32)
    with path.open('wb') as fh:
        fh.write(header)
        if sparse:
            fh.truncate(len(header) + offset - (1 if truncated else 0))


class Q8Preflight(unittest.TestCase):
    def test_accepts_original_q8_without_reading_table(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'native-Q8.gguf'
            gguf(path, sparse=True)  # sparse allocation: virtually 54 GB, almost no disk space
            result=preflight.locate(path)
            self.assertEqual(result['row_bytes'],170)
            self.assertEqual(result['rows'], 320001536)
            self.assertEqual(result['table_bytes'], 54400261120)
            self.assertEqual(result['source'],str(path))

    def test_rejects_old_iq4_sidecar(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'old-ple.gguf'; gguf(path,kind=20)
            with self.assertRaisesRegex(ValueError,'refusing IQ4_NL fallback'):
                preflight.locate(path)

    def test_rejects_missing_native_ple(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'no-ple.gguf'; gguf(path,kind=None)
            with self.assertRaisesRegex(ValueError, 'found 0'):
                preflight.locate(path)

    def test_rejects_incorrect_geometry(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'short-ple.gguf'; gguf(path,shape=(160,128))
            with self.assertRaisesRegex(ValueError, 'geometry'):
                preflight.locate(path)

    def test_rejects_truncation(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'truncated.gguf'; gguf(path,sparse=True,truncated=True)
            with self.assertRaisesRegex(ValueError, 'truncated'):
                preflight.locate(path)

    def test_rejects_missing_split(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'model-00001-of-00002.gguf'; gguf(path,sparse=True)
            with self.assertRaisesRegex(ValueError, 'missing GGUF shards'):
                preflight.locate(path)

    def test_profile_does_not_force_iq4_or_suppress_ple(self):
        p=Path(__file__).resolve().parents[1]/'tools/windows/q4-local-profiles/strata-unsloth-q8_0.json'
        data=json.loads(p.read_text())
        a=data['args']
        self.assertEqual(a[a.index('--ple-require-type')+1], 'Q8_0')
        self.assertNotIn('--ple-gguf', a)
        self.assertNotIn('--no-ple',a)
        self.assertIn('--native',a)
        self.assertTrue(data['exe'].startswith('E:\\ai\\Strata-Q4\\'))
        self.assertTrue(data['args'][a.index('--native')+1].startswith('R:\\q8-model\\'))

    def test_native_engine_enforces_requested_type_twice(self):
        s=(Path(__file__).resolve().parents[1]/'src/program/generate.cpp').read_text()
        self.assertIn('o.ple_require_type = next("--ple-require-type")',s)
        self.assertIn('pt->shape[1] != strata::kernels::PLE_TABLE_ROWS',s)
        self.assertIn('o.ple_require_type != ple_table.format()',s)
        self.assertIn('o.ple_gguf = o.native_shards[at]',s)


if __name__ == '__main__':
    unittest.main()
