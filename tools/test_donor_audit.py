"""No-network checks for the donor archive comparison tool."""
import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.donor_audit import manifest, compare, write_tsv


class Audit(unittest.TestCase):
    def make(self, path, entries):
        with zipfile.ZipFile(path, 'w') as z:
            for name, value in entries:
                z.writestr(name, value)

    def test_diff_keeps_all_categories(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d) / 'base.zip'
            donor = Path(d) / 'donor.zip'
            self.make(base, [('Strata/src/a.cpp', 'old'), ('Strata/serve/b.py', 'unchanged'),
                             ('Strata/tools/local.py', 'local')])
            self.make(donor, [('Strata-main/src/a.cpp', 'newer'), ('Strata-main/serve/b.py', 'unchanged'),
                              ('Strata-main/include/new.hpp', 'new')])
            rows = compare(manifest(str(base), 'Strata'), manifest(str(donor), 'Strata-main'))
            self.assertEqual({r['file']: r['status'] for r in rows},
                             {'src/a.cpp': 'changed', 'serve/b.py': 'identical',
                              'tools/local.py': 'custom_only', 'include/new.hpp': 'donor_only'})

    def test_rejects_duplicate_zip_members(self):
        import warnings
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'duplicate.zip'
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                self.make(path, [('Strata/a', '1'), ('Strata/a', '2')])
            with self.assertRaisesRegex(ValueError, 'duplicate'): manifest(str(path), 'Strata')

    def test_rejects_path_escape(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'escape.zip'
            self.make(path, [('Strata/../oops', '0')])
            with self.assertRaisesRegex(ValueError, 'unsafe'): manifest(str(path), 'Strata')

    def test_rejects_wrong_root(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'wrong.zip'
            self.make(path, [('Unexpected/file', '1')])
            with self.assertRaisesRegex(ValueError, 'unexpected root'): manifest(str(path), 'Strata')

    def test_tsv_has_five_columns_without_trailing_tabs(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'matrix.tsv'
            rows = compare({'ours': 10, 'same': 20},
                           {'theirs': 30, 'same': 20})
            write_tsv(str(path), rows)
            lines = path.read_text(encoding='utf-8').splitlines()
            self.assertEqual(len(lines), 4)
            self.assertTrue(all(len(line.split('\t')) == 5 for line in lines))
            self.assertTrue(all(not line.endswith((' ', '\t')) for line in lines))
            self.assertIn('ours\troot\tcustom_only\t10\t-', lines)
            self.assertIn('theirs\troot\tdonor_only\t-\t30', lines)
            self.assertEqual(next(r for r in rows if r['file'] == 'ours')['donor_bytes'], '')


if __name__ == '__main__':
    unittest.main()
