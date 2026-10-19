from __future__ import annotations
import json, tempfile, unittest
from pathlib import Path
from tools import personal_models
ROOT=Path(__file__).resolve().parent.parent
CAT=json.loads((ROOT/'data/personal_models.json').read_text(encoding='utf-8'))

class Profiles060(unittest.TestCase):
    def cfg(self,m): return json.loads((ROOT/Path(m['config'].replace('\\','/'))).read_text(encoding='utf-8'))
    def test_every_profile_parallel_two(self):
        for m in CAT['models']:
            self.assertEqual(self.cfg(m).get('parallel'),2,m['id'])
    def test_qwen4exp_defaults(self):
        for m in CAT['models']:
            if m['arch']!='qwen4exp': continue
            a=self.cfg(m)['args']
            self.assertEqual(a[a.index('--pcie-frac')+1],'0.09',m['id'])
            self.assertEqual(a[a.index('--spec-min-p')+1],'0.9',m['id'])
            self.assertEqual(a[a.index('--spec')+1],'4',m['id'])
            self.assertEqual(a[a.index('--mtp')+1],r'E:\ai\Strata-data\mtp\rt',m['id'])
    def test_q36_uses_embedded_mtp_not_flash_flags(self):
        for m in CAT['models']:
            if m['arch']!='qwen35moe': continue
            c=self.cfg(m); a=c['args']
            self.assertEqual(c.get('arch'),'qwen35moe')
            self.assertEqual(a[a.index('--mtp')+1],'2')
            self.assertIn('--batch-mtp',a)
            self.assertNotIn('--pcie-frac',a)
            self.assertNotIn('--spec-min-p',a)


    def test_legacy_ids_and_aliases_are_preserved(self):
        byid={m['id']:m for m in CAT['models']}
        for mid,alias in {
            'alesha_rco_iq3s':'alesha-rco-iq3s',
            'sc117_rco_iq3s':'sc117-rco-abliterated-iq3s',
            'huihui_q4':'huihui-q4-k-xl',
            'huihui_q8':'huihui-q8-0',
            'unsloth_q4':'unsloth-q4-k-xl',
            'unsloth_q6':'unsloth-q6-k',
            'unsloth_q8':'unsloth-q8-0',
            'personal_rco_iq3s':'personal-rco-iq3s',
        }.items():
            self.assertIn(mid,byid)
            self.assertIn(alias,byid[mid].get('aliases',[]))
        self.assertIn('additional_files',CAT)
    def test_quant_specific_contract_matches_existing_profiles(self):
        for m in CAT['models']:
            if m['arch']!='qwen4exp': continue
            a=self.cfg(m)['args']; q=m['quantization']
            if q=='IQ3_S':
                self.assertIn('--ple-gguf',a,m['id'])
                self.assertNotIn('--suffix-draft',a,m['id'])
                self.assertTrue(a[a.index('--ple-gguf')+1].endswith(m['files'][1]),m['id'])
            elif 'Q6_K' in q:
                self.assertEqual(a[a.index('--ple-require-type')+1],'Q8_0',m['id'])
                self.assertEqual(a[a.index('--resident-budget-gib')+1],'120',m['id'])
            elif q=='Q8_0':
                self.assertEqual(a[a.index('--ple-require-type')+1],'Q8_0',m['id'])
                self.assertEqual(a[a.index('--resident-budget-gib')+1],'120',m['id'])
            else:
                self.assertEqual(a[a.index('--resident-budget-gib')+1],'80',m['id'])
    def test_q36_vendor_engine_source_is_present(self):
        v=ROOT/'vendor/strata-q36-0.1.45'
        for rel in ['src/qwen35/q36_engine.cu','src/qwen35/q36_main.cpp','include/strata/qwen35/engine.hpp','CMakeLists.txt']:
            self.assertTrue((v/rel).is_file(),rel)
    def test_expected_local_variants(self):
        ids={m['id'] for m in CAT['models']}
        required={'alesha_rco_iq3s','sc117_rco_iq3s','personal_rco_iq3s','sc117-swift-rco-abliterated-iq3s',
                  'ukisai-swift-q4-k-m','ukisai-swift-q6-k','ukisai-swift-rco-iq3s','huihui_q4','huihui_q8',
                  'unsloth_q4','unsloth_q6','unsloth_q8','q36-ud-q8-k-xl','q36-uncensored-q8-k-xl'}
        self.assertTrue(required <= ids, required-ids)

    def test_future_q36_q8_glob_resolves_completed_file_only(self):
        m=next(x for x in CAT['models'] if x['id']=='q36-uncensored-q8-k-xl')
        with tempfile.TemporaryDirectory() as td:
            prefix=Path(td)
            d=prefix/'models'/'morikomorizz'/'Qwen3.6-35B-A3B-Uncensored-HauhauCS-MTP'
            d.mkdir(parents=True)
            # A partial download must never satisfy the profile.
            (d/'downloading_future-Q8_K_XL.gguf.part').write_bytes(b'x')
            r=personal_models.check(m,prefix,headers=False)
            self.assertEqual(r['status'],'downloading')
            # Once exactly one completed publisher filename appears, the wildcard resolves it.
            final=d/'publisher-final-uncensored-Q8_K_XL.gguf'
            final.write_bytes(b'GGUF')
            r=personal_models.check(m,prefix,headers=False)
            self.assertEqual(r['status'],'names_present_only')
            self.assertEqual(r['glob_match'],final.name)

    def test_personal_starter_keeps_catalog_config_read_only_for_glob(self):
        text=(ROOT/'START-PERSONAL-MODEL.ps1').read_text(encoding='utf-8')
        self.assertIn("model_glob", text)
        self.assertIn("runtime-configs", text)
        self.assertIn("$EffectiveConfigPath", text)
        self.assertNotIn("Set-Content -LiteralPath $ConfigPath", text)
if __name__=='__main__': unittest.main()
