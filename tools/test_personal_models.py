from __future__ import annotations
import json, tempfile, unittest
from pathlib import Path
from tools import personal_models

class CatalogTests(unittest.TestCase):
    def test_catalog_v2_loads_and_has_unique_ids(self):
        c=personal_models.load_catalog()
        self.assertEqual(c['schema_version'],2)
        ids=[m['id'] for m in c['models']]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertGreaterEqual(len(ids),17)
        self.assertEqual(c['defaults']['pcie_frac'],0.09)
        self.assertEqual(c['defaults']['spec_min_p'],0.9)
        self.assertEqual(c['defaults']['parallel'],2)

    def test_only_supported_architectures_get_profiles(self):
        c=personal_models.load_catalog()
        self.assertEqual({m['arch'] for m in c['models']},{'qwen4exp','qwen35moe'})
        reasons=' '.join(x['reason'] for x in c['unsupported_detected'])
        self.assertIn('27B', reasons)
        self.assertIn('Gemma', reasons)

    def test_downloading_profiles_are_retained(self):
        c=personal_models.load_catalog()
        pending={m['id'] for m in c['models'] if m.get('state')=='downloading'}
        self.assertIn('sc117-swift-rco-abliterated-iq3s',pending)
        self.assertIn('ukisai-swift-q4-k-m',pending)
        self.assertIn('ukisai-swift-q6-k',pending)
        self.assertIn('ukisai-swift-rco-iq3s',pending)
        self.assertIn('q36-uncensored-q8-k-xl',pending)

    def test_config_files_exist(self):
        root=Path(__file__).resolve().parent.parent
        for m in personal_models.load_catalog()['models']:
            self.assertTrue((root/Path(m['config'].replace('\\','/'))).is_file(),m['id'])

if __name__=='__main__': unittest.main()
