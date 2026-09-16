#!/usr/bin/env python3
"""Exercise snapshot publication and installation with real Git and LFS."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
RELEASE = os.environ.get('MCP_SNAPSHOT_RELEASE')


class IndexHooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='index-sharing-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo with spaces'
        self.repo.mkdir()
        self.env = {'PATH': os.environ['PATH'], 'HOME': str(self.base / 'home'),
                    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
                    'GIT_TERMINAL_PROMPT': '0', 'HF_HUB_OFFLINE': '1', 'TRANSFORMERS_OFFLINE': '1'}
        Path(self.env['HOME']).mkdir()
        for relative in ['.gitignore', 'scripts/index-snapshot-attributes.gitattributes', 'scripts/configure-vault.sh', 'scripts/configure-vault.py', 'scripts/configure-index-git.sh',
                         'scripts/check-index-snapshot.sh', 'scripts/prepare-index-snapshot.sh',
                         'scripts/install-index-snapshot.sh', 'scripts/index-snapshots.mjs',
                         'scripts/receive-index-snapshot.sh', 'scripts/hooks/post-merge.sh',
                         'scripts/hooks/post-checkout.sh', 'scripts/hooks/post-rewrite.sh',
                         'scripts/hooks/pre-commit.sh']:
            target = self.repo / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / relative, target)
        fixture = self.base / 'mcp fixture'
        shutil.copyfile(SOURCE / 'test/fixtures/snapshot-mcp.py', fixture)
        fixture.chmod(0o755)
        self.env['OBSIDIAN_SNAPSHOT_MCP'] = str(fixture)
        self.env['MCP_CMD'] = str(fixture)  # Used only by the shared-setup test with its own launcher.
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.install_hook()

    def run_cmd(self, *args, ok=True, cwd=None, extra_env=None):
        result = subprocess.run(args, cwd=cwd or self.repo, env=self.env | (extra_env or {}),
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout)
        return result

    def git(self, *args, **kw):
        return self.run_cmd('git', *args, **kw)

    def engine(self, *args, **kw):
        return self.run_cmd('node', 'scripts/index-snapshots.mjs', *args, **kw)

    def install_hook(self, **kw):
        return self.run_cmd('bash', 'scripts/configure-index-git.sh', **kw)

    def register(self, name='example', id='shared-example'):
        (self.repo / f'vaults/{name}').mkdir(parents=True, exist_ok=True)
        self.engine('register', '--vault', f'vaults/{name}', '--id', id)
        return id

    def write(self, name, text='Snapshotmarker preserves existing embeddings across machines.'):
        target = self.repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def baseline(self):
        self.register()
        self.write('vaults/example/note.md')
        self.git('add', '-A')
        self.git('commit', '-qm', 'baseline')

    def tree(self):
        return self.git('write-tree').stdout

    def inventory(self, name):
        folder = self.repo / name
        return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in folder.rglob('*') if p.is_file()} if folder.exists() else {}

    @unittest.skipUnless(shutil.which('git-lfs'), 'Git LFS required')
    def test_commit_publishes_only_shared_database_with_lfs_pointers(self):
        self.baseline()
        files = self.git('ls-files').stdout.splitlines()
        shared = '.obsidian-vault-mcp/shared/shared-example'
        database = [f for f in files if f.startswith(shared + '/lancedb/')]
        self.assertTrue(database)
        for name in database:
            self.assertIn('version https://git-lfs.github.com/spec/v1', self.git('show', f'HEAD:{name}').stdout)
        self.assertFalse(any('/vaults/shared-example/' in f for f in files))
        metadata = self.git('show', f'HEAD:{shared}/snapshot.json').stdout
        self.assertNotIn(str(self.repo), metadata)
        self.assertEqual(json.loads(metadata)['vaultId'], 'shared-example')
        self.assertEqual(self.git('status', '--porcelain').stdout, '')

    def test_unrelated_commits_skip_mcp(self):
        self.write('note.md')
        self.git('add', '-A')
        self.git('commit', '-qm', 'unregistered', extra_env={'OBSIDIAN_SNAPSHOT_MCP': '/missing'})

    def test_partial_and_untracked_notes_block_without_changing_staging(self):
        self.baseline()
        self.write('vaults/example/note.md', 'staged content')
        self.git('add', 'vaults/example/note.md')
        self.write('vaults/example/note.md', 'unstaged content')
        before = self.tree()
        result = self.git('commit', '-qm', 'partial', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Stage all Markdown changes', result.stdout)
        self.assertEqual(self.tree(), before)
        self.git('add', 'vaults/example/note.md')
        self.write('vaults/example/untracked.md')
        result = self.git('commit', '-qm', 'untracked', ok=False)
        self.assertIn('Stage all Markdown changes', result.stdout)

    def test_multiple_vault_failure_preserves_all_staged_and_shared_files(self):
        self.baseline()
        self.register('second', 'second-id')
        self.write('vaults/second/note.md')
        self.write('vaults/example/note.md', 'changed first vault')
        self.write('unrelated.txt', 'keep staged')
        self.git('add', '-A')
        before, shared = self.tree(), self.inventory('.obsidian-vault-mcp/shared')
        result = self.git('commit', '-qm', 'two vaults', ok=False, extra_env={'SNAPSHOT_FIXTURE_FAIL_ID': 'second-id'})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.tree(), before)
        self.assertEqual(self.inventory('.obsidian-vault-mcp/shared'), shared)
        self.assertFalse((self.repo / '.git/index.lock').exists())

    def test_multiple_vault_success_keeps_unrelated_staging(self):
        self.baseline()
        self.register('second', 'second-id')
        self.write('vaults/second/note.md')
        self.write('vaults/example/note.md', 'changed first vault')
        self.write('unrelated.txt', 'keep staged')
        self.git('add', '-A')
        self.git('commit', '-qm', 'two vaults')
        self.assertEqual(self.git('show', 'HEAD:unrelated.txt').stdout, 'keep staged')
        for id in ['shared-example', 'second-id']:
            self.assertTrue((self.repo / f'.obsidian-vault-mcp/shared/{id}/snapshot.json').is_file())

    def test_no_change_preserves_published_payload_mtimes(self):
        self.baseline()
        folder = self.repo / '.obsidian-vault-mcp/shared/shared-example'
        before = {p: p.stat().st_mtime_ns for p in folder.rglob('*') if p.is_file()}
        self.engine('prepare')
        self.assertEqual({p: p.stat().st_mtime_ns for p in before}, before)
        self.assertEqual(self.git('status', '--porcelain').stdout, '')

    def test_staging_failure_rolls_back_published_tree(self):
        self.baseline()
        self.write('vaults/example/note.md', 'a new snapshot')
        self.git('add', 'vaults/example/note.md')
        before, shared = self.tree(), self.inventory('.obsidian-vault-mcp/shared')
        self.git('config', 'filter.lfs.process', 'false')
        result = self.engine('prepare', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.tree(), before)
        self.assertEqual(self.inventory('.obsidian-vault-mcp/shared'), shared)

    def test_missing_staged_lfs_attributes_prevents_ordinary_git_blobs(self):
        self.register()
        self.write('vaults/example/note.md')
        self.git('add', '-A')
        self.git('rm', '--cached', '.gitattributes')
        before = self.tree()
        result = self.engine('prepare', ok=False)
        self.assertIn('staged LF attributes', result.stdout)
        self.assertEqual(self.tree(), before)

    def test_path_limited_publication_is_rejected_without_losing_staging(self):
        self.baseline()
        self.write('vaults/example/note.md', 'changed')
        self.write('unrelated.txt', 'staged')
        self.git('add', 'unrelated.txt')
        before = self.tree()
        result = self.git('commit', '-qm', 'only note', '--', 'vaults/example/note.md', ok=False)
        self.assertIn('path-limited commit', result.stdout)
        self.assertEqual(self.tree(), before)

    def test_commit_all_publishes_matching_snapshot_and_keeps_staged_files(self):
        self.baseline()
        self.write('vaults/example/note.md', 'commit all changed note\n')
        self.write('unrelated.txt', 'already staged')
        self.git('add', 'unrelated.txt')
        self.git('commit', '-am', 'commit all')
        hashes = json.loads(self.git('show', 'HEAD:.obsidian-vault-mcp/shared/shared-example/file-hashes.json').stdout)
        self.assertEqual(hashes['note.md'], hashlib.md5(b'commit all changed note\n').hexdigest())
        self.assertEqual(self.git('show', 'HEAD:unrelated.txt').stdout, 'already staged')
        self.assertEqual(self.git('status', '--porcelain').stdout, '')
        self.assertFalse((self.repo / '.git/index.lock').exists())
        self.assertFalse((self.repo / '.git/index.lock.lock').exists())

    def test_commit_all_failure_preserves_original_staging_and_published_files(self):
        self.baseline()
        self.write('vaults/example/note.md', 'new note content')
        self.write('unrelated.txt', 'staged only')
        self.git('add', 'unrelated.txt')
        before, shared = self.tree(), self.inventory('.obsidian-vault-mcp/shared')
        result = self.git('commit', '-am', 'failed indexing', ok=False,
                          extra_env={'SNAPSHOT_FIXTURE_INDEX_FAIL_ID': 'shared-example'})
        self.assertIn('fixture indexing failed', result.stdout)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.tree(), before)
        self.assertEqual(self.inventory('.obsidian-vault-mcp/shared'), shared)
        self.git('config', 'filter.lfs.process', 'false')
        result = self.git('commit', '-am', 'failed LFS staging', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.tree(), before)
        self.assertEqual(self.inventory('.obsidian-vault-mcp/shared'), shared)
        self.assertFalse((self.repo / '.git/index.lock').exists())
        self.assertFalse((self.repo / '.git/index.lock.lock').exists())

    def test_commit_all_in_linked_worktree_and_with_untracked_notes(self):
        self.baseline()
        linked = self.base / 'linked worktree'
        self.git('worktree', 'add', '-qb', 'linked-all', str(linked))
        (linked / 'vaults/example/note.md').write_text('tracked update')
        new_note = linked / 'vaults/example/new.md'
        new_note.write_text('new note needs staging')
        result = self.git('commit', '-am', 'untracked note', cwd=linked, ok=False)
        self.assertIn('Stage all Markdown changes', result.stdout)
        self.git('add', 'vaults/example/new.md', cwd=linked)
        self.git('commit', '-am', 'tracked and explicitly staged notes', cwd=linked)
        hashes = json.loads(self.git('show', 'HEAD:.obsidian-vault-mcp/shared/shared-example/file-hashes.json', cwd=linked).stdout)
        self.assertEqual(set(hashes), {'note.md', 'new.md'})
        self.assertEqual(self.git('status', '--porcelain', cwd=linked).stdout, '')

    def test_commit_all_can_retry_after_a_later_hook_rejects_commit(self):
        self.baseline()
        self.write('vaults/example/note.md', 'retry after commit-msg failure')
        self.write('unrelated.txt', 'already staged')
        self.git('add', 'unrelated.txt')
        before = self.tree()
        hook = self.repo / '.git/hooks/commit-msg'
        hook.write_text('#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        result = self.git('commit', '-am', 'rejected later', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.tree(), before)
        self.assertFalse((self.repo / '.git/index.lock').exists())
        self.assertFalse((self.repo / '.git/index.lock.lock').exists())
        # Publication succeeded, so generated working files remain for the retry.
        hashes = json.loads((self.repo / '.obsidian-vault-mcp/shared/shared-example/file-hashes.json').read_text())
        self.assertEqual(hashes['note.md'], hashlib.md5(b'retry after commit-msg failure').hexdigest())
        hook.unlink()
        self.git('add', '-A', '--', '.obsidian-vault-mcp/shared/shared-example')
        self.git('commit', '-am', 'retry')
        self.assertEqual(self.git('show', 'HEAD:unrelated.txt').stdout, 'already staged')
        self.assertEqual(self.git('status', '--porcelain').stdout, '')

    def test_arbitrary_alternate_index_remains_unsupported(self):
        self.baseline()
        self.write('vaults/example/note.md', 'alternate index note')
        alternative = self.repo / '.git/custom-index'
        shutil.copyfile(self.repo / '.git/index', alternative)
        env = {'GIT_INDEX_FILE': str(alternative)}
        self.git('add', 'vaults/example/note.md', extra_env=env)
        before = alternative.read_bytes()
        result = self.engine('hook', ok=False, extra_env=env)
        self.assertIn('alternate Git index', result.stdout)
        self.assertEqual(alternative.read_bytes(), before)

    def test_migration_untracks_live_files_but_keeps_local_data(self):
        self.register()
        self.write('vaults/example/note.md')
        old = self.write('.obsidian-vault-mcp/vaults/shared-example/lancedb/notes.lance/data/old.lance', 'old data')
        self.git('add', '-A')
        self.git('add', '-f', str(old.relative_to(self.repo)))
        self.git('-c', 'obsidian.snapshotPolicy=off', 'commit', '-qm', 'old layout')
        self.engine('migrate')
        self.assertEqual(old.read_text(), 'old data')
        self.assertNotIn(str(old.relative_to(self.repo)), self.git('ls-files').stdout)
        self.assertIn('.obsidian-vault-mcp/shared/', self.git('ls-files').stdout)

    def test_install_validates_payload_notes_and_lock(self):
        self.baseline()
        self.engine('install')
        live = '.obsidian-vault-mcp/vaults/shared-example'
        before = self.inventory(live)
        self.write('vaults/example/note.md', 'different notes')
        self.assertIn('Vault notes differ', self.engine('install', ok=False).stdout)
        self.assertEqual(self.inventory(live), before)
        self.git('restore', 'vaults/example/note.md')
        lock = self.write(live + '/index.lock', '{}')
        self.assertIn('locked', self.engine('install', ok=False).stdout)
        lock.unlink()
        self.write('.obsidian-vault-mcp/shared/shared-example/schema-version.json', 'broken')
        self.assertIn('incomplete or modified', self.engine('install', ok=False).stdout)
        self.assertEqual(self.inventory(live), before)

    def test_symlink_and_bad_options_are_rejected(self):
        self.baseline()
        self.assertIn('missing command option', self.engine('install', '--vault', ok=False).stdout)
        hashes = self.repo / '.obsidian-vault-mcp/shared/shared-example/file-hashes.json'
        hashes.unlink()
        hashes.symlink_to(self.repo / '.obsidian-indexes.json')
        self.assertIn('Symbolic links', self.engine('install', ok=False).stdout)

    def test_setup_preserves_hooks_and_custom_hook_paths(self):
        hook = self.repo / '.git/hooks/pre-commit'
        before = hook.read_bytes()
        prepush = (self.repo / '.git/hooks/pre-push').read_bytes()
        self.install_hook()
        self.assertEqual(hook.read_bytes(), before)
        self.assertEqual((self.repo / '.git/hooks/pre-push').read_bytes(), prepush)
        hook.write_text('#!/bin/sh\nexit 1\n')
        self.assertIn('Existing pre-commit hook preserved', self.install_hook().stdout)
        self.git('config', 'core.hooksPath', 'custom-hooks')
        self.assertIn('Custom core.hooksPath detected', self.install_hook().stdout)

    def test_linked_worktree_and_stable_id(self):
        self.baseline()
        linked = self.base / 'different clone name'
        self.git('worktree', 'add', '-qb', 'linked', str(linked))
        result = self.engine('register', '--vault', 'vaults/example', '--id', 'different-id', cwd=linked)
        self.assertEqual(result.stdout.strip(), 'shared-example')
        (linked / 'vaults/example/note.md').write_text('changed in linked worktree')
        self.git('add', 'vaults/example/note.md', cwd=linked)
        self.git('commit', '-qm', 'linked', cwd=linked)
        manifest = json.loads((linked / '.obsidian-vault-mcp/shared/shared-example/snapshot.json').read_text())
        self.assertEqual(manifest['vaultId'], 'shared-example')

    def test_shared_setup_reuses_registered_id(self):
        self.register()
        self.write('vaults/example/existing.md', 'Existing vault')
        self.run_cmd('bash', 'scripts/configure-vault.sh', '--skip-index', extra_env={
            'MCP_CMD': 'python3 ' + str(SOURCE / 'test/fixtures/snapshot-mcp.py')})
        config = json.loads((self.repo / '.obsidian-indexes.json').read_text())
        self.assertEqual(config['vaults'], [{'path': 'vaults/example', 'id': 'shared-example'}])

    def test_default_model_rules_removed_only_after_models_are_untracked(self):
        self.git('lfs', 'track', '.obsidian-vault-mcp/**/*.onnx')
        model = self.write('.obsidian-vault-mcp/models/model.onnx', 'model')
        self.git('add', '-f', str(model.relative_to(self.repo)))
        self.assertIn('Tracked model files found', self.install_hook().stdout)
        self.assertIn('filter: lfs', self.git('check-attr', 'filter', '--', str(model.relative_to(self.repo))).stdout)
        self.git('rm', '--cached', '--', str(model.relative_to(self.repo)))
        self.install_hook()
        self.assertEqual(model.read_text(), 'model')
        self.assertIn('filter: unspecified', self.git('check-attr', 'filter', '--', str(model.relative_to(self.repo))).stdout)

    def test_unstaged_deregistration_cannot_bypass_required_publication(self):
        self.baseline()
        config = self.repo / '.obsidian-indexes.json'
        original = config.read_bytes()
        self.write('vaults/example/note.md', 'changed note')
        self.git('add', 'vaults/example/note.md')
        before = self.tree()
        for replacement in [b'{"version":1,"vaults":[]}', None]:
            with self.subTest(replacement=replacement):
                if replacement is None:
                    config.unlink()
                else:
                    config.write_bytes(replacement)
                result = self.git('commit', '-qm', 'must not bypass', ok=False)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('Stage the current .obsidian-indexes.json', result.stdout)
                self.assertEqual(self.tree(), before)
                config.write_bytes(original)

    def test_staged_registration_publishes_already_tracked_notes(self):
        self.write('vaults/example/note.md')
        self.git('add', '-A')
        self.git('commit', '-qm', 'unregistered vault')
        self.register()
        self.git('add', '.obsidian-indexes.json')
        self.git('commit', '-qm', 'register existing notes')
        self.assertTrue((self.repo / '.obsidian-vault-mcp/shared/shared-example/snapshot.json').exists())

    def test_explicit_staged_deregistration_is_allowed(self):
        self.baseline()
        self.write('.obsidian-indexes.json', '{"version":1,"vaults":[]}')
        self.write('vaults/example/note.md', 'intentionally unregistered')
        self.git('add', '.obsidian-indexes.json', 'vaults/example/note.md')
        self.git('commit', '-qm', 'deregister', extra_env={'OBSIDIAN_SNAPSHOT_MCP': '/missing'})
        self.assertEqual(json.loads(self.git('show', 'HEAD:.obsidian-indexes.json').stdout)['vaults'], [])
        self.git('rm', '.obsidian-indexes.json')
        self.git('commit', '-qm', 'remove registration file')

    def test_setup_enforces_lf_for_notes_registration_metadata_and_hooks(self):
        names = ['vaults/example/note.md', '.obsidian-indexes.json',
                 '.obsidian-vault-mcp/shared/shared-example/file-hashes.json',
                 'scripts/hooks/post-merge.sh', 'scripts/index-snapshots.mjs']
        for name in names:
            with self.subTest(name=name):
                self.assertIn('eol: lf', self.git('check-attr', 'eol', '--', name).stdout)
        before = (self.repo / '.gitattributes').read_bytes()
        self.install_hook()
        self.assertEqual((self.repo / '.gitattributes').read_bytes(), before)

    def test_crlf_working_notes_have_actionable_migration_and_preserve_staging(self):
        self.baseline()
        self.git('config', 'core.autocrlf', 'true')
        note = self.repo / 'vaults/example/note.md'
        note.write_bytes(b'first line\r\nsecond line\r\n')
        self.git('add', 'vaults/example/note.md')
        before = self.tree()
        result = self.git('commit', '-qm', 'CRLF edit', ok=False)
        self.assertIn('CRLF', result.stdout)
        self.assertIn('normalize-text', result.stdout)
        self.assertEqual(self.tree(), before)
        self.engine('normalize-text', '--vault', 'vaults/example')
        self.assertEqual(note.read_bytes(), b'first line\nsecond line\n')
        self.assertEqual(self.tree(), before)
        self.git('add', '--renormalize', 'vaults/example')
        self.git('commit', '-qm', 'normalized edit')
        hashes = json.loads(self.git('show', 'HEAD:.obsidian-vault-mcp/shared/shared-example/file-hashes.json').stdout)
        self.assertEqual(hashes['note.md'], hashlib.md5(note.read_bytes()).hexdigest())

    def test_autocrlf_receiver_checks_out_matching_lf_payload(self):
        self.baseline()
        self.write('vaults/example/note.md', 'first line\nsecond line\n')
        self.git('add', 'vaults/example/note.md')
        self.git('commit', '-qm', 'LF content')
        receiver = self.receiver(autocrlf='true')
        self.assertEqual((receiver / 'vaults/example/note.md').read_bytes(), b'first line\nsecond line\n')
        self.assertNotIn(b'\r\n', (receiver / '.obsidian-indexes.json').read_bytes())
        self.assertEqual(self.received_hashes(receiver)['note.md'], hashlib.md5(b'first line\nsecond line\n').hexdigest())
        self.assertEqual(self.git('status', '--porcelain', cwd=receiver).stdout, '')

    def test_legacy_crlf_blobs_require_renormalization_after_conversion(self):
        self.register()
        attrs = self.repo / '.gitattributes'
        attrs.write_text(attrs.read_text().replace('vaults/**/*.md text eol=lf\n', ''))
        note = self.write('vaults/example/note.md')
        note.write_bytes(b'legacy\r\ncontent\r\n')
        self.git('add', '-A')
        self.git('-c', 'obsidian.snapshotPolicy=off', 'commit', '-qm', 'legacy CRLF')
        self.install_hook()
        before = self.tree()
        self.engine('normalize-text')
        self.assertEqual(self.tree(), before)
        result = self.git('commit', '-qm', 'not restaged', ok=False)
        # Explicit preparation also checks the old staged CRLF bytes.
        result = self.engine('prepare', ok=False)
        self.assertIn('CRLF', result.stdout)
        self.assertIn('staged vaults/example/note.md', result.stdout)
        self.git('add', '--renormalize', '.gitattributes', 'vaults/example')
        self.git('commit', '-qm', 'LF migration')
        self.assertEqual(self.git('show', 'HEAD:vaults/example/note.md').stdout, 'legacy\ncontent\n')
        self.assertEqual(json.loads(self.git('show', 'HEAD:.obsidian-vault-mcp/shared/shared-example/file-hashes.json').stdout)['note.md'], hashlib.md5(note.read_bytes()).hexdigest())

    def test_normalizer_repairs_crlf_checkouts_and_respects_live_writer_lock(self):
        self.baseline()
        self.engine('install')
        config = self.repo / '.obsidian-indexes.json'
        config.write_bytes(config.read_bytes().replace(b'\n', b'\r\n'))
        note = self.repo / 'vaults/example/note.md'
        note.write_bytes(b'changed\r\nnote\r\n')
        shared = self.repo / '.obsidian-vault-mcp/shared/shared-example'
        manifest = shared / 'snapshot.json'
        manifest.write_bytes(manifest.read_bytes().replace(b'\n', b'\r\n'))
        live = self.repo / '.obsidian-vault-mcp/vaults/shared-example'
        metadata = live / 'index-metadata.json'
        metadata.write_bytes(metadata.read_bytes().replace(b'\n', b'\r\n'))
        lock = live / 'index.lock'
        lock.write_text('{}')
        before = self.tree()
        result = self.engine('normalize-text', ok=False)
        self.assertIn('locked', result.stdout)
        self.assertIn(b'\r\n', note.read_bytes())
        self.assertIn(b'\r\n', config.read_bytes())
        lock.unlink()
        self.engine('normalize-text')
        self.assertEqual(self.tree(), before)
        for file in [note, config, manifest, metadata]:
            self.assertNotIn(b'\r\n', file.read_bytes())
        # Conversion preserves content differences; it does not hide stale snapshots.
        result = self.engine('install', ok=False)
        self.assertIn('Vault notes differ', result.stdout)

    def test_normalizer_validates_shared_inventory_before_converting(self):
        self.baseline()
        shared = self.repo / '.obsidian-vault-mcp/shared/shared-example'
        files = [shared / name for name in ['file-hashes.json', 'index-metadata.json', 'schema-version.json']]
        original = {file: file.read_bytes() + b'\n' for file in files}
        manifest = json.loads((shared / 'snapshot.json').read_text())
        for file, content in original.items():
            entry = next(item for item in manifest['files'] if item['path'] == file.name)
            entry.update(bytes=len(content), sha256=hashlib.sha256(content).hexdigest())
        (shared / 'snapshot.json').write_text(json.dumps(manifest))
        for file, content in original.items():
            file.write_bytes(content.replace(b'\n', b'\r\n'))
        self.engine('normalize-text')
        for file, content in original.items():
            self.assertEqual(file.read_bytes(), content)
        self.engine('install')
        # An inventory that actually describes CRLF bytes needs a new export.
        metadata = shared / 'index-metadata.json'
        metadata.write_bytes(metadata.read_bytes().replace(b'\n', b'\r\n'))
        manifest = json.loads((shared / 'snapshot.json').read_text())
        entry = next(item for item in manifest['files'] if item['path'] == 'index-metadata.json')
        entry.update(bytes=len(metadata.read_bytes()), sha256=hashlib.sha256(metadata.read_bytes()).hexdigest())
        (shared / 'snapshot.json').write_text(json.dumps(manifest))
        note = self.repo / 'vaults/example/note.md'
        note.write_bytes(b'changed\r\nnote\r\n')
        before = self.inventory('.obsidian-vault-mcp/shared')
        result = self.engine('normalize-text', ok=False)
        self.assertIn('without invalidating its snapshot inventory', result.stdout)
        self.assertEqual(self.inventory('.obsidian-vault-mcp/shared'), before)
        self.assertEqual(note.read_bytes(), b'changed\r\nnote\r\n')

    def test_conflicting_note_attributes_block_before_indexing(self):
        self.baseline()
        self.write('vaults/example/.gitattributes', '*.md text eol=crlf\n')
        self.write('vaults/example/note.md', 'changed\n')
        self.git('add', 'vaults/example')
        log = self.base / 'calls.jsonl'
        result = self.engine('prepare', ok=False, extra_env={'SNAPSHOT_FIXTURE_LOG': str(log)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('LF attributes', result.stdout)
        self.assertFalse(log.exists())

    def test_attribute_only_commits_validate_root_and_nested_rules(self):
        self.baseline()
        self.write('vaults/example/folder/note.md')
        self.git('add', 'vaults/example/folder/note.md')
        self.git('commit', '-qm', 'nested note')
        shared = self.inventory('.obsidian-vault-mcp/shared/shared-example')
        log = self.base / 'attribute-calls.jsonl'
        cases = [
            ('.gitattributes', '*.md text eol=crlf'),
            ('vaults/.gitattributes', '*.md text eol=crlf'),
            ('vaults/example/.gitattributes', '*.md text eol=crlf'),
            ('vaults/example/folder/.gitattributes', '*.md text eol=crlf'),
            ('.obsidian-vault-mcp/.gitattributes', '*.json text eol=crlf'),
            ('.obsidian-vault-mcp/shared/.gitattributes', '*.json text eol=crlf'),
            ('scripts/.gitattributes', '*.sh text eol=crlf'),
        ]
        for relative, rule in cases:
            with self.subTest(relative=relative):
                attributes = self.repo / relative
                previous = attributes.read_text() if attributes.exists() else ''
                self.write(relative, previous + '\n' + rule + '\n')
                self.git('add', '--', relative)
                before = self.tree()
                result = self.git('commit', '-qm', 'attributes only', ok=False,
                                  extra_env={'SNAPSHOT_FIXTURE_LOG': str(log)})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('LF attributes', result.stdout)
                self.assertEqual(self.tree(), before)
                self.assertEqual(self.inventory('.obsidian-vault-mcp/shared/shared-example'), shared)
                self.assertFalse(log.exists())
                self.git('restore', '--source=HEAD', '--staged', '--worktree', '--', relative)

    def test_attribute_only_commits_validate_staged_rules_even_when_working_rules_are_safe(self):
        self.baseline()
        attributes = self.repo / '.gitattributes'
        original = attributes.read_text()
        attributes.write_text(original + '\n*.md text eol=crlf\n')
        self.git('add', '.gitattributes')
        attributes.write_text(original)
        before = self.tree()
        result = self.git('commit', '-qm', 'unsafe staged rules', ok=False)
        self.assertIn('staged LF attributes', result.stdout)
        self.assertEqual(self.tree(), before)

    def test_attribute_deletion_cannot_expose_incompatible_inherited_rules(self):
        self.baseline()
        attributes = self.repo / '.gitattributes'
        attributes.write_text(attributes.read_text() + '\n*.md text eol=crlf\n')
        self.write('vaults/example/.gitattributes', '*.md text eol=lf\n')
        self.git('add', '.gitattributes', 'vaults/example/.gitattributes')
        self.git('commit', '-qm', 'safe nested override')
        self.git('rm', 'vaults/example/.gitattributes')
        before = self.tree()
        result = self.git('commit', '-qm', 'remove override', ok=False)
        self.assertIn('LF attributes', result.stdout)
        self.assertEqual(self.tree(), before)

    def test_attribute_only_commit_cannot_delete_root_policy(self):
        self.baseline()
        self.git('rm', '.gitattributes')
        before = self.tree()
        result = self.git('commit', '-qm', 'remove root attributes', ok=False)
        self.assertIn('LF attributes', result.stdout)
        self.assertEqual(self.tree(), before)

    def test_attribute_files_cannot_be_added_inside_snapshot_payload(self):
        self.baseline()
        self.write('.obsidian-vault-mcp/shared/shared-example/.gitattributes', '*.json text eol=lf\n')
        self.git('add', '.obsidian-vault-mcp/shared/shared-example/.gitattributes')
        before = self.tree()
        result = self.git('commit', '-qm', 'attributes inside snapshot', ok=False,
                          extra_env={'OBSIDIAN_SNAPSHOT_MCP': '/missing'})
        self.assertIn('outside the immutable snapshot', result.stdout)
        self.assertEqual(self.tree(), before)
        # Repair a previously bypassed commit without requiring an indexer.
        self.git('-c', 'obsidian.snapshotPolicy=off', 'commit', '-qm', 'legacy misplaced attributes')
        self.git('rm', '.obsidian-vault-mcp/shared/shared-example/.gitattributes')
        self.git('commit', '-qm', 'remove misplaced attributes', extra_env={'OBSIDIAN_SNAPSHOT_MCP': '/missing'})

    def test_attribute_only_commits_preserve_lfs_filters(self):
        self.baseline()
        self.write('.obsidian-vault-mcp/shared/.gitattributes', '*.lance -filter\n')
        self.git('add', '.obsidian-vault-mcp/shared/.gitattributes')
        before = self.tree()
        result = self.git('commit', '-qm', 'disable database filter', ok=False)
        self.assertIn('Git filter', result.stdout)
        self.assertEqual(self.tree(), before)

    def test_safe_attribute_only_commits_skip_mcp_and_preserve_unstaged_notes(self):
        self.baseline()
        shared = self.inventory('.obsidian-vault-mcp/shared/shared-example')
        note = self.write('vaults/example/note.md', 'keep this edit unstaged')
        for relative, rule in [('.gitattributes', '# harmless root change'),
                               ('vaults/example/.gitattributes', '*.md text eol=lf'),
                               ('.obsidian-vault-mcp/shared/.gitattributes', '*.json text eol=lf'),
                               ('docs/.gitattributes', '*.md text eol=crlf')]:
            with self.subTest(relative=relative):
                attributes = self.repo / relative
                previous = attributes.read_text() if attributes.exists() else ''
                self.write(relative, previous + '\n' + rule + '\n')
                self.git('add', '--', relative)
                self.git('commit', '-qm', 'safe attributes', extra_env={'OBSIDIAN_SNAPSHOT_MCP': '/missing'})
                self.assertEqual(note.read_text(), 'keep this edit unstaged')
                self.assertNotEqual(self.git('show', 'HEAD:vaults/example/note.md').stdout, note.read_text())
                self.assertEqual(self.inventory('.obsidian-vault-mcp/shared/shared-example'), shared)

    def test_size_limit_and_staged_config(self):
        self.register()
        self.write('vaults/example/note.md')
        self.git('add', '-A')
        self.git('config', 'obsidian.snapshotMaxBytes', '1')
        self.assertIn('snapshotMaxBytes', self.engine('prepare', ok=False).stdout)
        self.git('config', '--unset', 'obsidian.snapshotMaxBytes')
        config = self.repo / '.obsidian-indexes.json'
        config.write_text(config.read_text() + '\n')
        self.assertIn('Stage the current', self.engine('prepare', ok=False).stdout)

    def receiver(self, autocrlf=None):
        self.git('branch', '-M', 'main')
        remote = self.base / 'remote.git'
        self.git('init', '--bare', '-q', str(remote))
        self.git('--git-dir', str(remote), 'symbolic-ref', 'HEAD', 'refs/heads/main')
        self.git('remote', 'add', 'origin', str(remote))
        self.git('push', '-u', 'origin', 'main')
        receiver = self.base / 'receiver'
        self.git('clone', '-q', *(['-c', 'core.autocrlf=' + autocrlf] if autocrlf else []), str(remote), str(receiver))
        self.install_hook(cwd=receiver, extra_env={'OBSIDIAN_SNAPSHOT_MCP': '/missing'})
        return receiver

    def received_hashes(self, receiver):
        return json.loads((receiver / '.obsidian-vault-mcp/vaults/shared-example/file-hashes.json').read_text())

    def test_commit_indexes_before_export_and_manual_policy_skips_indexing(self):
        log = self.base / 'calls.jsonl'
        self.env['SNAPSHOT_FIXTURE_LOG'] = str(log)
        self.baseline()
        calls = [json.loads(line)['operation'] for line in log.read_text().splitlines()]
        self.assertEqual(calls, ['obsidian_rag_index', 'obsidian_prepare_index_snapshot'])
        log.write_text('')
        self.git('config', 'obsidian.snapshotAutoIndex', 'false')
        self.engine('prepare')
        self.assertEqual(json.loads(log.read_text())['operation'], 'obsidian_prepare_index_snapshot')

    def test_indexing_failure_blocks_commit_without_changing_staging(self):
        self.baseline()
        self.write('vaults/example/note.md', 'new text')
        self.git('add', 'vaults/example/note.md')
        before, shared = self.tree(), self.inventory('.obsidian-vault-mcp/shared')
        failed = self.git('commit', '-qm', 'failed indexing', ok=False,
                          extra_env={'SNAPSHOT_FIXTURE_INDEX_FAIL_ID': 'shared-example'})
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('fixture indexing failed', failed.stdout)
        self.assertEqual(self.tree(), before)
        self.assertEqual(self.inventory('.obsidian-vault-mcp/shared'), shared)

    def test_all_vaults_are_checked_before_indexing(self):
        self.baseline()
        self.register('second', 'second-id')
        self.write('vaults/second/note.md')
        self.git('add', '-A')
        self.write('vaults/second/note.md', 'unstaged')
        log = self.base / 'calls.jsonl'
        self.assertNotEqual(self.engine('prepare', ok=False, extra_env={'SNAPSHOT_FIXTURE_LOG': str(log)}).returncode, 0)
        self.assertFalse(log.exists())

    def test_pull_installs_changed_snapshot_and_fetches_skipped_lfs_objects(self):
        self.baseline()
        receiver = self.receiver()
        before = self.received_hashes(receiver)
        self.write('vaults/example/note.md', 'new text on producer')
        self.git('add', 'vaults/example/note.md')
        self.git('commit', '-qm', 'new snapshot')
        self.git('push')
        result = self.git('pull', '--ff-only', cwd=receiver,
                          extra_env={'GIT_LFS_SKIP_SMUDGE': '1', 'OBSIDIAN_SNAPSHOT_MCP': '/missing'})
        self.assertIn('Installed shared index', result.stdout)
        self.assertNotEqual(self.received_hashes(receiver), before)
        self.assertEqual(self.git('status', '--porcelain', cwd=receiver).stdout, '')
        metadata = receiver / '.obsidian-vault-mcp/vaults/shared-example/index-metadata.json'
        mtime = metadata.stat().st_mtime_ns
        self.write('unrelated.txt', 'unrelated')
        self.git('add', 'unrelated.txt')
        self.git('commit', '-qm', 'unrelated')
        self.git('push')
        self.git('pull', '--ff-only', cwd=receiver)
        self.assertEqual(metadata.stat().st_mtime_ns, mtime)

    def test_branch_switch_installs_corresponding_snapshot(self):
        self.baseline()
        first = self.git('rev-parse', '--abbrev-ref', 'HEAD').stdout.strip()
        self.git('switch', '-c', 'alternate')
        self.write('vaults/example/note.md', 'alternate branch')
        self.git('add', 'vaults/example/note.md')
        self.git('commit', '-qm', 'alternate snapshot')
        self.git('switch', first)
        before = self.received_hashes(self.repo)
        self.git('switch', 'alternate')
        self.assertNotEqual(self.received_hashes(self.repo), before)
        self.assertEqual(self.git('status', '--porcelain').stdout, '')

    def test_pull_rebase_installs_only_after_replay(self):
        self.baseline()
        receiver = self.receiver()
        (receiver / 'local.txt').write_text('local commit')
        self.git('config', 'user.name', 'Receiver', cwd=receiver)
        self.git('config', 'user.email', 'receiver@example.invalid', cwd=receiver)
        self.git('add', 'local.txt', cwd=receiver)
        self.git('commit', '-qm', 'local commit', cwd=receiver)
        self.write('vaults/example/note.md', 'remote snapshot')
        self.git('add', 'vaults/example/note.md')
        self.git('commit', '-qm', 'remote change')
        self.git('push')
        output = self.git('pull', '--rebase', cwd=receiver).stdout
        self.assertEqual(output.count('Installed shared index'), 1, output)
        self.assertEqual(self.received_hashes(receiver)['note.md'], hashlib.md5(b'remote snapshot').hexdigest())
        self.assertEqual((receiver / 'local.txt').read_text(), 'local commit')

    def test_receive_failure_leaves_live_index_and_reports_completed_git_update(self):
        self.baseline()
        receiver = self.receiver()
        before = self.received_hashes(receiver)
        self.write('vaults/example/note.md', 'remote change')
        self.git('add', 'vaults/example/note.md')
        self.git('commit', '-qm', 'remote change')
        self.git('push')
        lock = receiver / '.obsidian-vault-mcp/vaults/shared-example/index.lock'
        lock.write_text('{}')
        result = self.git('pull', '--ff-only', cwd=receiver, ok=False)
        self.assertIn('installation failed', result.stdout)
        self.assertIn('Keep the MCP stopped', result.stdout)
        self.assertEqual(self.git('rev-parse', 'HEAD', cwd=receiver).stdout, self.git('rev-parse', 'HEAD').stdout)
        self.assertEqual(self.received_hashes(receiver), before)
        lock.unlink()
        self.engine('install', cwd=receiver)
        self.assertNotEqual(self.received_hashes(receiver), before)

    def test_receive_opt_out_and_file_checkout_leave_live_index_alone(self):
        self.baseline()
        receiver = self.receiver()
        before = self.received_hashes(receiver)
        self.git('config', 'obsidian.snapshotInstall', 'off', cwd=receiver)
        self.write('vaults/example/note.md', 'remote update')
        self.git('add', 'vaults/example/note.md')
        self.git('commit', '-qm', 'remote')
        self.git('push')
        self.git('pull', '--ff-only', cwd=receiver)
        self.assertEqual(self.received_hashes(receiver), before)
        self.git('config', 'obsidian.snapshotInstall', 'auto', cwd=receiver)
        self.git('checkout', '--', 'vaults/example/note.md', cwd=receiver)
        self.assertEqual(self.received_hashes(receiver), before)

    def test_noop_install_refreshes_checkout_timestamps_without_copying_database(self):
        self.baseline()
        self.engine('install')
        live = self.repo / '.obsidian-vault-mcp/vaults/shared-example'
        payload = next((live / 'lancedb').rglob('*.lance'))
        before = payload.stat().st_mtime_ns
        note = self.repo / 'vaults/example/note.md'
        os.utime(note, (note.stat().st_atime, note.stat().st_mtime + 2))
        self.engine('receive', 'post-merge', '0')
        metadata = json.loads((live / 'index-metadata.json').read_text())
        self.assertAlmostEqual(metadata['latestMtimeMs'], note.stat().st_mtime * 1000, delta=1)
        self.assertEqual(payload.stat().st_mtime_ns, before)

    def test_receive_skips_squash_merge_and_rejects_uncommitted_manifest(self):
        self.baseline()
        self.engine('install')
        before = self.inventory('.obsidian-vault-mcp/vaults/shared-example')
        manifest = self.repo / '.obsidian-vault-mcp/shared/shared-example/snapshot.json'
        manifest.write_text(manifest.read_text() + '\n')
        self.engine('receive', 'post-merge', '1')
        result = self.engine('receive', 'post-merge', '0', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.inventory('.obsidian-vault-mcp/vaults/shared-example'), before)

    def test_setup_preserves_custom_receive_hook_and_installs_remaining_hooks(self):
        hook = self.repo / '.git/hooks/post-merge'
        custom = '#!/bin/sh\n# custom merge handler\nexit 0\n'
        hook.write_text(custom)
        self.assertIn('Existing post-merge hook preserved', self.install_hook().stdout)
        self.assertEqual(hook.read_text(), custom)
        for event in ['post-checkout', 'post-rewrite', 'pre-commit', 'pre-push']:
            self.assertTrue(os.access(self.repo / '.git/hooks' / event, os.X_OK))

    @unittest.skipUnless(RELEASE, 'Set MCP_SNAPSHOT_RELEASE to the installed published package directory')
    def test_published_mcp_release_survives_lfs_push_clone_and_install(self):
        release = Path(RELEASE).resolve()
        package = json.loads((release / 'package.json').read_text())
        self.assertEqual(package['version'], '2.1.0')
        self.assertEqual(package['dependencies']['@lancedb/lancedb'], '0.27.2')
        runner = self.base / 'real-mcp'
        runner.write_text('#!/usr/bin/env python3\nimport os,sys\nos.execvp("node", ["node", '+repr(str(release / 'dist/index.js'))+']+sys.argv[1:])\n')
        runner.chmod(0o755)
        self.env['OBSIDIAN_SNAPSHOT_MCP'] = str(runner)
        self.register()
        self.git('config', 'core.autocrlf', 'input')
        self.write('vaults/example/note.md', 'Snapshotmarker preserves existing embeddings across machines.\n')
        self.write('vaults/example/empty.md', '')
        self.run_cmd('node', str(SOURCE / 'test/fixtures/seed-lancedb.mjs'), str(release), str(self.repo), 'vaults/example', 'shared-example')
        self.git('add', '-A')
        lock = self.repo / '.obsidian-vault-mcp/vaults/shared-example/index.lock'
        lock.write_text(json.dumps({'pid': os.getpid()}))
        blocked = self.engine('prepare', ok=False, extra_env={'OBSIDIAN_INDEX_LOCK_WAIT_MS': '0'})
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn('lock', blocked.stdout)
        self.assertTrue(lock.exists())
        lock.unlink()
        self.git('commit', '-qm', 'real export')
        self.engine('prepare')
        self.assertEqual(self.git('status', '--porcelain').stdout, '')
        remote = self.base / 'remote.git'
        self.git('init', '--bare', '-q', str(remote))
        self.git('--git-dir', str(remote), 'symbolic-ref', 'HEAD', 'refs/heads/main')
        self.git('remote', 'add', 'origin', str(remote))
        self.git('push', 'origin', 'HEAD:main')
        receiver = self.base / 'receiver'
        self.git('clone', '-q', '-c', 'core.autocrlf=true', str(remote), str(receiver))
        self.install_hook(cwd=receiver)
        self.write('vaults/example/new-empty.md', '')
        self.git('add', 'vaults/example/new-empty.md')
        self.git('commit', '-qam', 'incremental empty note')
        self.git('push', 'origin', 'HEAD:main')
        self.git('pull', '--ff-only', cwd=receiver, extra_env={'GIT_LFS_SKIP_SMUDGE': '1'})
        self.assertIn('new-empty.md', self.received_hashes(receiver))
        metadata = receiver / '.obsidian-vault-mcp/vaults/shared-example/index-metadata.json'
        before = metadata.read_bytes()
        result = self.run_cmd(str(runner), 'obsidian_rag_index', '--vault_path', str(receiver / 'vaults/example'),
                              '--workspace_path', str(receiver), '--vault_id', 'shared-example', cwd=receiver,
                              extra_env={'OBSIDIAN_VAULT_PATH': str(receiver / 'vaults/example'),
                                         'OBSIDIAN_WORKSPACE_PATH': str(receiver), 'OBSIDIAN_VAULT_ID': 'shared-example'})
        self.assertIn('no changes detected', result.stdout)
        self.assertEqual(metadata.read_bytes(), before)
        code = '''const {createRequire}=require('node:module'); const r=createRequire(process.argv[1]+'/package.json');
        (async()=>{const db=await r('@lancedb/lancedb').connect(process.argv[2]);const table=await db.openTable('notes');
        const rows=await table.query().toArray();const fts=await table.search('Snapshotmarker','fts').toArray();
        const vector=await table.vectorSearch(Array.from(rows[0].vector)).toArray();
        console.log(JSON.stringify({rows:rows.length,fts:fts.length,vector:vector.length,text:rows[0].text}));
        table.close();db.close()})().catch(e=>{console.error(e);process.exitCode=1})'''
        result = self.run_cmd('node', '-e', code, str(release), str(receiver / '.obsidian-vault-mcp/vaults/shared-example/lancedb'))
        self.assertEqual(json.loads(result.stdout), {'rows': 1, 'fts': 1, 'vector': 1, 'text': 'Snapshotmarker preserves existing embeddings across machines.\n'})
        self.assertEqual(self.git('status', '--porcelain', cwd=receiver).stdout, '')


if __name__ == '__main__':
    unittest.main(verbosity=2)
