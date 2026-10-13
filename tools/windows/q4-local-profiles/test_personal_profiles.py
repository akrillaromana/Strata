"""Offline static integrity checks for the owner's fixed-path Strata launch profiles.

These checks deliberately do not start PowerShell, CUDA, Strata, or manipulate R:.
"""
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
PROFILE = ROOT / 'tools/windows/q4-local-profiles'
DEPLOY = ROOT / 'PERSONAL_START_E_ai_Strata-Q4-Fork'

CORE = (
    'START-HERE.bat', 'START-HERE-HUIHUI.bat', 'START-HERE IQ3_S.bat',
    'START-HERE Q8_0.bat',
    'START-Q4-RAM.ps1', 'START-HUIHUI-Q4-RAM.ps1', 'START-IQ3S-RAM.ps1',
    'START-Q8-RAM.ps1',
    'PREPARE-HUIHUI-Q4.py', 'START-QUALITY-RAM.ps1',
    'strata-unsloth-ud-q4_k_xl-RAM.json',
    'strata-huihui-ud-q4_k_xl-RAM.json', 'strata-iq3_s-RAM.json',
    'strata-unsloth-ud-q4_k_xl.json', 'strata-unsloth-q8_0.json',
)

class TestPersonalProfiles(unittest.TestCase):
    def test_mirror_identical(self):
        names = {p.name for p in PROFILE.iterdir() if p.is_file() and p.name != 'test_personal_profiles.py'}
        self.assertEqual(names, {p.name for p in DEPLOY.iterdir() if p.is_file()})
        for name in names:
            with self.subTest(name=name):
                self.assertEqual((PROFILE / name).read_bytes(), (DEPLOY / name).read_bytes())

    def test_expected_launchers_and_flat_dependents(self):
        for name in CORE:
            with self.subTest(name=name):
                self.assertTrue((PROFILE / name).is_file())

    def test_fixed_personal_paths(self):
        for name in ('START-Q4-RAM.ps1', 'START-HUIHUI-Q4-RAM.ps1', 'START-IQ3S-RAM.ps1', 'START-Q8-RAM.ps1'):
            txt = (PROFILE / name).read_text('utf-8-sig')
            with self.subTest(name=name):
                self.assertIn('E:\\ai\\Strata-Q4-Fork', txt)
                self.assertIn('E:\\ai\\Strata-data', txt)
                self.assertIn('R:\\', txt)
                self.assertIn('C:\\Program Files\\AIM Toolkit', txt)
                self.assertIn('$PSScriptRoot', txt) if name == 'START-HUIHUI-Q4-RAM.ps1' else None
                self.assertIn('Existing configuration', txt) if name not in ('START-HUIHUI-Q4-RAM.ps1', 'START-Q8-RAM.ps1') else None
                if name != 'START-Q8-RAM.ps1':
                    self.assertIn('ConvertFrom-Json', txt)
                    self.assertIn('[System.IO.File]::Replace', txt)
                else:
                    self.assertIn('Write-StrataModelConfiguration', txt)
                self.assertNotIn('Set-Content -LiteralPath $Cfg', txt)

    def test_spec_min_p_agrees_with_live_json(self):
        pairs = (
            ('START-Q4-RAM.ps1', 'strata-unsloth-ud-q4_k_xl-RAM.json'),
            ('START-HUIHUI-Q4-RAM.ps1', 'strata-huihui-ud-q4_k_xl-RAM.json'),
            ('START-IQ3S-RAM.ps1', 'strata-iq3_s-RAM.json'),
        )
        for script, config in pairs:
            with self.subTest(script=script):
                txt = (PROFILE / script).read_text('utf-8-sig')
                matches = re.findall(r'"--spec-min-p",\s*"([0-9.]+)"', txt)
                data = json.loads((PROFILE / config).read_text('utf-8-sig'))
                args = data['args']
                if script == 'START-IQ3S-RAM.ps1':
                    self.assertIn('--spec-min-p', txt)
                    self.assertIn('$EffectiveSpecMinP = 0.75', txt)
                    self.assertEqual(args[args.index('--spec-min-p')+1], '0.75')
                else:
                    self.assertEqual(len(matches), 1)
                    self.assertEqual(args[args.index('--spec-min-p')+1], matches[0])
                self.assertEqual(data['cwd'], 'E:\\ai\\Strata-Q4-Fork')
                self.assertEqual(data['exe'], 'E:\\ai\\Strata-Q4-Fork\\engine\\strata.exe')
                self.assertEqual(data['port'], 8080)

    def test_huihui_hash_checks_and_sampling(self):
        txt = (PROFILE / 'START-HUIHUI-Q4-RAM.ps1').read_text('utf-8-sig')
        self.assertIn("'Verifying the copied Huihui PLE by SHA256", txt)
        self.assertIn('RAM pack index matches Huihui source', txt)
        self.assertIn('$PreviousConfigText', txt)
        self.assertIn('repeat_stop_tokens', txt)
        c = json.loads((PROFILE / 'strata-huihui-ud-q4_k_xl-RAM.json').read_text('utf-8-sig'))
        self.assertEqual(c['sampling']['temperature'], 0)
        self.assertEqual(c['sampling']['top_k'], 1)
        self.assertEqual(c['repeat_stop_tokens'], 64)

    def test_native_q8_requires_its_own_ngram(self):
        data = json.loads((PROFILE / 'strata-unsloth-q8_0.json').read_text('utf-8-sig'))
        args = data['args']
        self.assertNotIn('--ple-gguf', args)
        self.assertNotIn('--no-ple', args)
        self.assertIn('--native', args)
        self.assertEqual(args[args.index('--ple-require-type')+1], 'Q8_0')
        self.assertIn('Q8_0 n-gram', (PROFILE / 'README_RU.md').read_text('utf-8'))

    def test_q8_launcher_safety_and_q4_python_fallback(self):
        q8 = (PROFILE / 'START-Q8-RAM.ps1').read_text('utf-8-sig')
        self.assertIn('q8_ple_preflight.py', q8)
        self.assertIn('Assert-StrataModelServerStopped', q8)
        self.assertIn('Get-FileHash', q8)
        self.assertIn("'--ple-require-type', 'Q8_0'", q8)
        self.assertIn('Q8_0 PLE', q8)
        self.assertNotIn('IQ4_NL', q8)
        for name in ('START-Q4-RAM.ps1', 'START-HUIHUI-Q4-RAM.ps1'):
            source = (PROFILE / name).read_text('utf-8-sig')
            self.assertIn('Resolve-StrataModelPython', source)
            self.assertIn('Initialize-StrataModelDlls', source)
            self.assertIn('if (-not $Detached)', source)
            self.assertNotIn('$Python,$Server,$Engine', source)

    def test_static_q4_has_server_reasoning_budget_not_engine_flag(self):
        data = json.loads((PROFILE/'strata-unsloth-ud-q4_k_xl.json').read_text('utf-8'))
        self.assertNotIn('--reasoning_budget_tokens', data['args'])
        self.assertEqual(data['reasoning_budget_tokens'], 10240)

    def test_no_accidental_runtime_objects(self):
        for p in DEPLOY.iterdir():
            self.assertNotIn(p.suffix.lower(), ('.gguf', '.exe', '.log', '.bak', '.bin', '.tmp', '.zip'))

if __name__ == '__main__':
    unittest.main()
