from __future__ import annotations
import json
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class Q6LaunchBundle(unittest.TestCase):
    def test_bundle_files_exist(self):
        for rel in [
            'BUILD-Q6-ENGINE.ps1','BUILD-Q6-ENGINE.bat','SETUP-Q6.bat','START-Q6-RAM.ps1','START-Q6-K.bat','START-HERE Q6_K.bat',
            'PREPARE-Q6.bat','TUNE-Q6.bat','BENCHMARK-Q6.bat','TEST-Q6.bat','VERIFY-Q6.bat','VERIFY-Q6-API.ps1','GET-Q6-DIAGNOSTICS.ps1','GET-Q6-DIAGNOSTICS.bat',
            'tools/q6_ple_preflight.py','strata-unsloth-q6_k-RAM.json',
            'PERSONAL_START_E_ai_Strata-Q4-Fork/START-Q6-RAM.ps1',
            'PERSONAL_START_E_ai_Strata-Q4-Fork/strata-unsloth-q6_k-RAM.json']:
            self.assertTrue((ROOT/rel).is_file(), rel)
    def test_separate_engine_and_build_flags(self):
        text=(ROOT/'BUILD-Q6-ENGINE.ps1').read_text(encoding='utf-8')
        self.assertIn('STRATA_Q6K_EXPERTS=ON',text)
        self.assertIn('STRATA_MMQ_KQUANTS=ON',text)
        self.assertIn("'engine-q6'",text)
        self.assertNotRegex(text,r'Get-FileHash|SHA-?256|IncrementalHash')
    def test_launcher_read_only_config_and_no_hash(self):
        text=(ROOT/'START-Q6-RAM.ps1').read_text(encoding='utf-8')
        self.assertIn('New-StrataModelRuntimeConfig',text)
        self.assertIn('точному размеру',text)
        self.assertNotRegex(text,r'Get-FileHash|SHA-?256|IncrementalHash')
        self.assertIn('PleToRam',text)
    def test_config_is_q6_engine(self):
        cfg=json.loads((ROOT/'strata-unsloth-q6_k-RAM.json').read_text(encoding='utf-8'))
        self.assertEqual(cfg['model_name'],'qwen3.8-flash-next-unsloth-q6_k')
        self.assertTrue(cfg['exe'].endswith(r'engine-q6\strata.exe'))
        self.assertEqual(cfg['args'][cfg['args'].index('--resident-budget-gib')+1],'120')
        self.assertEqual(cfg['args'][cfg['args'].index('--spec-min-p')+1],'0.9')
        self.assertEqual(cfg['args'][cfg['args'].index('--pcie-frac')+1],'0.26')
        self.assertEqual(cfg['args'][cfg['args'].index('--ple-require-type')+1],'Q8_0')
    def test_mtp_one_still_in_grid(self):
        text=(ROOT/'TUNE-MODEL.ps1').read_text(encoding='utf-8')
        self.assertRegex(text,r'1\.0')
    def test_q6_inventory_exact_five_shard(self):
        data=json.loads((ROOT/'data/personal_models.json').read_text(encoding='utf-8'))
        q6=next(x for x in data['models'] if x['id']=='unsloth_q6')
        self.assertEqual(q6['shards'],5)
        self.assertEqual(q6['shard_stem'],'Qwen3.8-Flash-Next-Q6_K')
    def test_q6_defaults_match_q8_exactly_except_model_specific_paths(self):
        q8=json.loads((ROOT/'strata-unsloth-q8_0.json').read_text(encoding='utf-8'))
        q6=json.loads((ROOT/'strata-unsloth-q6_k-RAM.json').read_text(encoding='utf-8'))
        def normalized(cfg):
            args=list(cfg['args'])
            for flag in ('--pack','--native','--expert-profile','--mtp'):
                i=args.index(flag); args[i+1]=f'<{flag}>'
            return args
        self.assertEqual(normalized(q6), normalized(q8))
        for key in ('cwd','lib_dirs','port','gpu','gpus_asked'):
            self.assertEqual(q6[key],q8[key])
    def test_prefill_test_covers_q6(self):
        text=(ROOT/'tests/cuda/prefill_mmq_kquant_test.cpp').read_text(encoding='utf-8')
        self.assertIn('Q6_K gate/up',text)
        self.assertNotIn('Q6_K should not be covered',text)

if __name__=='__main__': unittest.main()
