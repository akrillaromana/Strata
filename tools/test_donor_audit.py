"""No-network checks for the donor archive comparison tool."""
import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.donor_audit import manifest, compare


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
            self.make(donor, [('Strata-main/src/a.cpp', 'new'), ('Strata-main/serve/b.py', 'unchanged'),
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


if __name__ == '__main__':
    unittest.main()
