"""Verify that stale metadata and migration tampering fail the offline checker."""
import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('check_contract', ROOT / 'scripts/check_contract.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ContractChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ['README.md', 'AGENTS.md', 'CHANGELOG.md', 'schema-version.json']:
            shutil.copyfile(ROOT / name, self.root / name)
        for name in ['supabase', 'docs', 'tests']:
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns('__pycache__'))

    def test_current_contract_passes(self):
        self.assertEqual(checker.validate(self.root), [])

    def test_released_migration_tampering_fails(self):
        path = next((self.root / 'supabase/migrations').glob('*.sql'))
        path.write_bytes(path.read_bytes() + b'\n-- modified\n')
        self.assertTrue(any('checksum mismatch' in e for e in checker.validate(self.root)))

    def test_unregistered_migration_fails(self):
        (self.root / 'supabase/migrations/20261115000100_unregistered.sql').write_text('select 1;')
        self.assertTrue(any('inventory differ' in e for e in checker.validate(self.root)))

    def test_outdated_readme_notice_fails(self):
        path = self.root / 'README.md'
        path.write_text(path.read_text(encoding='utf-8').replace('SCHEMA CONTRACT: 1.0.0', 'SCHEMA CONTRACT: 0.9.0'), encoding='utf-8')
        self.assertTrue(any('README top notice' in e for e in checker.validate(self.root)))


if __name__ == '__main__':
    unittest.main()
