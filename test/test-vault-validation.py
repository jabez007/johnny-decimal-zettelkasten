#!/usr/bin/env python3
"""Check public validation results for template assets and malformed vaults."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ValidationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='jd-validation-')
        self.addCleanup(self.temp.cleanup)
        self.vault = Path(self.temp.name) / 'vault'
        shutil.copytree(ROOT/'references/vault-starter', self.vault)

    def validate(self, expected=True, vault=None):
        result = subprocess.run(['python3', str(ROOT/'scripts/vault_validation.py'),
                                 str(vault or self.vault)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)
        return result.stdout

    def note(self, name='AGNT.11.01-An-approved-project-rule-has-an-explicit-scope.md', **fields):
        path = self.vault/'AGNT/10-Procedural_Rules/11-Coding'/name
        path.parent.mkdir(parents=True, exist_ok=True)
        defaults = {'entities': '[Testing]', 'communities': '[Agent Procedural Memory]', 'status': 'crystallized'}
        defaults.update(fields)
        path.write_text('---\n' + '\n'.join(f'{key}: {value}' for key, value in defaults.items())
                        + '\n---\n[[AGNT.00.00]]\n\n# An approved project rule has an explicit scope\n')
        return path

    def test_shipped_assets_follow_the_same_rules(self):
        self.validate(vault=ROOT/'references/vault-starter')
        self.validate(vault=ROOT/'vaults/example')

    def test_duplicate_ids_do_not_depend_on_the_title(self):
        self.note()
        self.note('AGNT.11.01-A-second-title-cannot-reuse-an-ID.md')
        self.assertIn('Duplicate ID AGNT.11.01', self.validate(False))

    def test_metadata_types_status_and_placeholders(self):
        self.note(entities='Testing', communities='[<community>]', status='redirect')
        output = self.validate(False)
        for field in ['entities', 'communities', 'status']:
            self.assertIn(field, output)

    def test_reserved_ids_and_misplaced_notes(self):
        self.note('AGNT.11.00-Category-indexes-are-invalid.md')
        self.note('AGNT.21.01-A-note-cannot-claim-another-category.md')
        output = self.validate(False)
        self.assertIn('Reserved identifier', output)
        self.assertIn('Folder placement', output)

    def test_missing_bases_navigation_and_link_targets(self):
        path = self.note()
        path.write_text(path.read_text().replace('[[AGNT.00.00]]', '[[missing]]'))
        (self.vault/'_SYS/JDEX_AGNT.base').unlink()
        output = self.validate(False)
        self.assertIn('First body line', output)
        self.assertIn('Unresolved wikilink [[missing]]', output)
        self.assertIn('JDEX_AGNT.base', output)

    def test_duplicate_yaml_fields_are_rejected(self):
        path = self.note()
        path.write_text(path.read_text().replace('status: crystallized', 'status: crystallized\nstatus: distilled'))
        self.assertIn('Duplicate YAML key', self.validate(False))

    def test_journals_do_not_require_permanent_metadata(self):
        journal = self.vault/'JRNL/AGNT/capture.md'
        journal.parent.mkdir(parents=True)
        journal.write_text('# Capture\nA raw observation with [[unreviewed idea]].\n')
        self.note()
        self.validate()

    def test_label_casing_and_ambiguous_links_require_review(self):
        first = self.note(aliases='[Shared alias]')
        self.note('AGNT.11.02-Another-rule-has-a-separate-identity.md',
                  entities='[testing]', aliases='[Shared alias]')
        first.write_text(first.read_text() + '\nThis relates to [[Shared alias]].\n')
        output = self.validate(False)
        self.assertIn('Inconsistent entities casing', output)
        self.assertIn('Ambiguous wikilink', output)

    def test_symlinked_notes_are_rejected(self):
        note = self.note()
        (note.parent/'AGNT.11.02-A-link-does-not-own-an-ID.md').symlink_to(note.name)
        self.assertIn('Symlinks are unsupported', self.validate(False))


if __name__ == '__main__':
    unittest.main(verbosity=2)
