#!/usr/bin/env python3
"""Exercise catalogue adoption through the public read-only commands."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CATALOGUE = '_SYS/metadata-catalogue.yaml'


class CatalogueTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='jd-catalogue-')
        self.addCleanup(self.temp.cleanup)
        self.vault = Path(self.temp.name)/'vault'
        shutil.copytree(ROOT/'references/vault-starter', self.vault)

    def command(self, script, *args, success=True):
        result = subprocess.run(['python3', str(ROOT/'scripts'/script), *map(str, args)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout+result.stderr)
        return result

    def catalogue(self, text):
        (self.vault/CATALOGUE).write_text(text)

    def note(self, communities, path='AGNT/10-Procedural_Rules/11-Coding/AGNT.11.01-Testing-requires-review.md'):
        note = self.vault/path
        note.parent.mkdir(parents=True, exist_ok=True)
        note.write_text('---\nentities: [Testing, New entity]\ncommunities: '+json.dumps(communities)+
                        '\nstatus: distilled\naliases: [A note title]\n---\n[[AGNT.00.00]]\n\nKeep this body.\n')
        return note

    def snapshot(self):
        return {p.relative_to(self.vault).as_posix(): p.read_bytes()
                for p in self.vault.rglob('*') if p.is_file()}

    def test_inventory_counts_notes_and_reports_source_paths_without_writing(self):
        note = self.note(['Coding Standards', 'Coding Standards'])
        self.note(['Old journal label'], 'JRNL/AGNT/capture.md')
        before = self.snapshot()
        report = json.loads(self.command('metadata_catalogue.py', 'inventory', self.vault).stdout)
        self.assertEqual(report['communities']['Coding Standards'],
                         {'count': 1, 'notes': [note.relative_to(self.vault).as_posix()]})
        self.assertIn('New entity', report['entities'])
        self.assertNotIn('Old journal label', report['communities'])
        report = json.loads(self.command('metadata_catalogue.py', 'inventory', self.vault, '--include-journals').stdout)
        self.assertIn('Old journal label', report['communities'])
        self.assertEqual(before, self.snapshot())

    def test_legacy_adoption_warns_and_strict_validation_requires_canonical_labels(self):
        self.note(['Coding Conventions', 'Unknown label'])
        result = self.command('vault_validation.py', self.vault)
        self.assertIn('WARN:', result.stdout)
        self.assertIn("use 'Coding Standards'", result.stdout)
        self.assertIn('Unknown community', result.stdout)
        self.command('vault_validation.py', self.vault, '--strict-metadata', success=False)
        (self.vault/CATALOGUE).unlink()
        self.assertIn('Missing _SYS/metadata-catalogue.yaml', self.command('vault_validation.py', self.vault).stdout)
        self.command('vault_validation.py', self.vault, '--strict-metadata', success=False)

    def test_filters_expand_declared_synonyms_and_observed_case_variants(self):
        self.note(['coding standards'])
        self.note(['CODING CONVENTIONS'], 'JRNL/AGNT/capture.md')
        report = json.loads(self.command('metadata_catalogue.py', 'filters', self.vault,
                                        'Coding Conventions', '--include-journals').stdout)
        self.assertEqual(report['canonical'], 'Coding Standards')
        self.assertEqual(report['communities'],
                         ['Coding Standards', 'Coding Conventions', 'CODING CONVENTIONS', 'coding standards'])
        unknown = self.command('metadata_catalogue.py', 'filters', self.vault, 'A note title')
        self.assertEqual(json.loads(unknown.stdout)['communities'], [])
        self.assertIn('unfiltered query', unknown.stderr)

    def test_plan_preserves_unknown_labels_and_journals_and_checks_source_hashes(self):
        note = self.note(['Coding Conventions', 'coding standards', 'Unknown label'])
        self.note(['Coding Conventions'], 'JRNL/AGNT/capture.md')
        before = self.snapshot()
        report = json.loads(self.command('metadata_catalogue.py', 'plan', self.vault).stdout)
        self.assertEqual(len(report['changes']), 1)
        change = report['changes'][0]
        self.assertEqual(change['after'], {'communities': ['Coding Standards', 'Unknown label']})
        self.assertEqual(change['expected_sha256'], hashlib.sha256(note.read_bytes()).hexdigest())
        self.assertEqual(report['catalogue_sha256'], hashlib.sha256((self.vault/CATALOGUE).read_bytes()).hexdigest())
        self.assertEqual(report['unresolved'][0]['label'], 'Unknown label')
        self.assertEqual(before, self.snapshot())

    def test_schema_rejects_unsupported_versions_and_ambiguous_labels(self):
        invalid = [
            'version: 2\ncommunities: {}\n',
            'version: true\ncommunities: {}\n',
            'version: 1\nversion: 1\ncommunities: {}\n',
            'version: 1\ncommunities: []\n',
            'version: 1\ncommunities:\n  A: {synonyms: []}\n',
            'version: 1\ncommunities:\n  A: {description: A, synonyms: other}\n',
            'version: 1\ncommunities:\n  A: {description: A, synonyms: [<placeholder>]}\n',
            'version: 1\ncommunities:\n  A: {description: A, synonyms: [B]}\n  B: {description: B}\n',
            'version: 1\ncommunities:\n  A: {description: A, synonyms: [Shared]}\n  B: {description: B, synonyms: [shared]}\n',
            'version: 1\ncommunities:\n  A: {description: A}\n  a: {description: a}\n',
            'version: 1\ncommunities:\n  A: {description: A, synonyms: [A]}\n',
            'version: 1\ncommunities:\n  A: {description: A, synonyms: [B, B]}\n',
        ]
        for text in invalid:
            with self.subTest(catalogue=text):
                self.catalogue(text)
                self.command('vault_validation.py', self.vault, success=False)
                self.command('metadata_catalogue.py', 'filters', self.vault, 'A', success=False)

    def test_inventory_reports_bad_yaml_and_label_types(self):
        note = self.note(['Coding Standards'])
        note.write_text('---\nentities: Wrong type\ncommunities: [Coding Standards]\n---\nBody\n')
        report = json.loads(self.command('metadata_catalogue.py', 'inventory', self.vault, success=False).stdout)
        self.assertIn('entities must be a list', report['errors'][0])
        note.write_text('---\ncommunities: [unfinished\n---\nBody\n')
        self.command('metadata_catalogue.py', 'plan', self.vault, success=False)

    def test_free_form_journals_with_empty_frontmatter_do_not_consume_the_body(self):
        path = self.note(['Coding Standards'], 'JRNL/AGNT/capture.md')
        path.write_text('---\n---\n\n# Capture\n\n- **Raw evidence**: unfinished thought\n\n---\n')
        report = json.loads(self.command('metadata_catalogue.py', 'inventory', self.vault,
                                        '--include-journals').stdout)
        self.assertEqual(report['errors'], [])
        self.assertIn('JRNL/AGNT/capture.md', report['unlabelled_notes'])
        self.command('metadata_catalogue.py', 'filters', ROOT/'vaults/example',
                     'Agent Procedural Memory', '--include-journals')

    def test_cross_system_communities_do_not_change_folder_rules(self):
        self.note(['Coding Standards'])
        self.command('vault_validation.py', self.vault, '--strict-metadata')
        note = self.note(['Coding Standards'], 'AGNT/10-Procedural_Rules/11-Coding/AGNT.21.01-Wrong-placement.md')
        self.assertIn('Folder placement', self.command('vault_validation.py', self.vault,
                                                      '--strict-metadata', success=False).stdout)

    def test_symlinks_and_missing_catalogue_fail_without_changes(self):
        path = self.vault/CATALOGUE
        path.unlink()
        self.command('metadata_catalogue.py', 'plan', self.vault, success=False)
        path.symlink_to(ROOT/'references/vault-starter'/CATALOGUE)
        self.command('metadata_catalogue.py', 'plan', self.vault, success=False)
        path.unlink()
        shutil.copyfile(ROOT/'references/vault-starter'/CATALOGUE, path)
        note = self.note(['Coding Standards'])
        (self.vault/'linked.md').symlink_to(note)
        self.command('metadata_catalogue.py', 'inventory', self.vault, success=False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
