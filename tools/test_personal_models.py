"""Inventory contracts for the supported personal model catalog; no real GGUF weights needed."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import personal_models as p


class PersonalModelsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = p.load_catalog()
        cls.models = {m['id']: m for m in cls.catalog['models']}

    def test_all_eight_model_variants_and_shard_counts(self):
        expected = {'alesha_rco_iq3s': 2, 'sc117_rco_iq3s': 2,
                    'personal_rco_iq3s': 2, 'huihui_q8': 6, 'huihui_q4': 4,
                    'unsloth_q6': 5, 'unsloth_q8': 6, 'unsloth_q4': 4}
        self.assertEqual({k: v['shards'] for k, v in self.models.items()}, expected)

    def test_q8_native_ple_is_required_for_both_producers(self):
        for name in ('huihui_q8', 'unsloth_q8'):
            with self.subTest(name=name):
                self.assertEqual(self.models[name]['ple_policy'], 'native_q8_only')
        self.assertTrue(all(m['ple_policy'] != 'native_q8_only'
                            for key, m in self.models.items() if key not in ('huihui_q8', 'unsloth_q8')))

    def test_both_rco_variants_have_independent_shard_stems(self):
        self.assertIn('GSQ-RCO-IQ3_S', self.models['alesha_rco_iq3s']['shard_stem'])
        self.assertIn('GSQ-RCO-abliterated-IQ3_S', self.models['sc117_rco_iq3s']['shard_stem'])
        self.assertIn(r'\Strata-data\models\IQ3_S', self.models['personal_rco_iq3s']['directory'])

    def test_source_names_match_real_user_inventory(self):
        self.assertTrue(self.models['unsloth_q6']['shard_stem'].endswith('-Q6_K'))
        self.assertTrue(self.models['unsloth_q8']['shard_stem'].endswith('-Q8_0'))
        self.assertEqual(len(self.catalog['additional_files']['unsloth']['mtp_ggufs']), 4)
        self.assertEqual(len(self.catalog['additional_files']['unsloth']['mmproj']), 2)

    def test_path_mapping_and_no_cross_family_shard_mix(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = Path(tmp) / 'ai'
            files = p.paths_for(self.models['huihui_q8'], prefix)
            self.assertEqual(len(files), 6)
            self.assertEqual(files[0].name, 'Qwen3.8-Flash-Next-Q8_0-00001-of-00006.gguf')
            self.assertEqual(files[-1].name, 'Qwen3.8-Flash-Next-Q8_0-00006-of-00006.gguf')
            self.assertEqual(files[0].parent, prefix/'models'/'huihui-ai'/'Huihui-Qwen3.8-Flash-Next-abliterated-GGUF')
            self.assertEqual(p.paths_for(self.models['personal_rco_iq3s'], prefix)[0].parent,
                             prefix/'Strata-data'/'models'/'IQ3_S')

    def test_missing_shards_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = p.check(self.models['unsloth_q6'], Path(tmp))
            self.assertEqual(result['status'], 'missing_shards')
            self.assertEqual(result['missing_shards'], [1, 2, 3, 4, 5])
            self.assertFalse(result['engine_runtime_verified'])

    def test_names_only_reports_existing_without_claiming_runtime_support(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for file in p.paths_for(self.models['alesha_rco_iq3s'], root):
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b'not a GGUF')
            evidence = p.check(self.models['alesha_rco_iq3s'], root, headers=False)
            self.assertEqual(evidence['status'], 'names_present_only')
            self.assertFalse(evidence['engine_runtime_verified'])
            invalid = p.check(self.models['alesha_rco_iq3s'], root, headers=True)
            self.assertEqual(invalid['status'], 'invalid_headers_or_paths')

    def test_q8_non_native_ple_fails_even_when_other_headers_look_valid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for file in p.paths_for(self.models['huihui_q8'], root):
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b'GGUF')
            metadata = {'architecture': 'qwen4exp', 'quantization_by_role': {},
                        'ple_table': {'type': 'IQ4_NL', 'native_reader_type': True},
                        'warnings': []}
            with patch.object(p, 'inspect_gguf', return_value=metadata):
                result = p.check(self.models['huihui_q8'], root)
            self.assertEqual(result['status'], 'native_q8_ple_unavailable')

    def test_reject_malicious_inventory_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            document = json.loads(json.dumps(self.catalog))
            document['models'][0]['directory'] = r'E:\ai\..\secrets'
            path = Path(tmp) / 'catalog.json'
            path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ValueError, 'unexpected personal model directory'):
                p.load_catalog(path)

    def test_catalog_and_individual_models_do_not_require_model_data(self):
        self.assertEqual(p.main(['--list', '--model', 'unsloth_q6']), 0)
        with self.assertRaises(SystemExit):
            p.main(['--list', '--model', 'unknown_model'])


if __name__ == '__main__':
    unittest.main()
