#!/usr/bin/env python3
"""Exercise complete setup with isolated homes and deterministic external CLIs."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('installer', SOURCE / 'scripts/install-global.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

STUB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['SETUP_CALLS'], 'a') as f:
    f.write(json.dumps({'cli': name, 'args': args, 'cwd': os.getcwd()})+'\n')
if name == 'codex':
    installed = [{'name': 'obsidian-vault-mcp', 'installed': True, 'enabled': True}] if os.environ.get('SETUP_EXISTING_PLUGIN') else []
    print(json.dumps({'marketplaces': [], 'installed': installed}))
elif name == 'claude':
    print('[]')
elif name == 'gemini':
    print('')
elif name == 'npx':
    ops = [i for i,a in enumerate(args) if a.startswith('obsidian_')]
    if not ops:
        if '--help' in args: sys.exit(0)
        for line in sys.stdin:
            message = json.loads(line)
            if message['method'] == 'initialize':
                result = {'protocolVersion': '2024-11-05', 'capabilities': {}, 'serverInfo': {'name': 'fixture', 'version': '1'}}
            elif message['method'] == 'tools/call':
                params = message['params']['arguments']
                if os.environ.get('SETUP_FAIL_CREATE') == params['file_path']:
                    result = {'isError': True, 'content': [{'type': 'text', 'text': 'creation failed'}]}
                else:
                    target = Path(params['vault_path'])/params['file_path']
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with target.open('x') as f: f.write(params['content'])
                    result = {'content': [{'type': 'text', 'text': 'Created note'}]}
            else:
                continue
            print(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'result': result}), flush=True)
        sys.exit(0)
    op, args = args[ops[0]], args[ops[0]+1:]
    params = dict(zip(args[::2], args[1::2]))
    config_path = Path.home()/'.obsidian-mcp.config.json'
    if op == 'obsidian_set_vault':
        config_path.write_text(json.dumps({'vault_path': params['--path'], 'workspace_path': params['--workspace_path'], 'vault_id': params['--vault_id']}))
        print('{}')
    elif op == 'obsidian_get_config':
        print(config_path.read_text())
    elif op == 'obsidian_rag_index':
        print(json.dumps({'success': not bool(os.environ.get('SETUP_FAIL_INDEX'))}))
    elif op == 'obsidian_rag_query':
        print('No relevant notes found.' if os.environ.get('SETUP_EMPTY_QUERY') else 'File: 00.00.md\nRelevance: 1\nVault Index')
    else:
        print('Unexpected operation: '+op, file=sys.stderr); sys.exit(1)
'''


class SetupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='jd-setup-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'vault repo'
        self.home = self.base / 'home'
        self.other = self.base / 'unrelated project'
        self.bin = self.base / 'bin'
        for directory in [self.repo, self.home, self.other, self.bin]:
            directory.mkdir()
        for directory in ['scripts', 'references', '.agents', '.claude', '.codex', '.gemini', '.opencode']:
            shutil.copytree(SOURCE / directory, self.repo / directory)
        for name in ['.gitattributes', '.gitignore', 'opencode.json', 'AGENTS.md', 'CLAUDE.md', 'GEMINI.md']:
            shutil.copyfile(SOURCE / name, self.repo / name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('GIT_', 'OBSIDIAN_', 'CODEX_', 'GEMINI_', 'CLAUDE_', 'XDG_', 'MCP_', 'OPENCODE_'))}
        self.env.update(HOME=str(self.home), PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                        SETUP_CALLS=str(self.base/'calls.jsonl'))
        for name in ['claude', 'codex', 'gemini', 'opencode', 'npx']:
            target = self.bin / name
            target.write_text(STUB)
            target.chmod(0o755)
        self.run_cmd('git', 'init', '-q', str(self.repo))
        self.run_cmd('git', 'init', '-q', str(self.other))

    def run_cmd(self, *args, ok=True, extra=None):
        result = subprocess.run(args, cwd=self.other, env=self.env | (extra or {}), stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def setup(self, harness, *args, **kwargs):
        return self.run_cmd('bash', str(self.repo/f'.{harness}/setup-environment.sh'), *args, **kwargs)

    def calls(self):
        path = self.base/'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_all_harnesses_install_global_research_and_keep_management_local(self):
        global_paths = {
            'claude': ('.claude/CLAUDE.md', '.claude/skills'),
            'codex': ('.codex/AGENTS.md', '.agents/skills'),
            'gemini': ('.gemini/GEMINI.md', '.gemini/skills'),
            'opencode': ('.config/opencode/AGENTS.md', '.config/opencode/skills'),
        }
        for harness, (rules, skills) in global_paths.items():
            with self.subTest(harness=harness):
                result = self.setup(harness, '--vault', 'My Notes')
                self.assertIn('Semantic retrieval returned a note', result.stdout)
                policy = (self.home/rules).read_text()
                self.assertIn('not MCP access controls', policy)
                self.assertIn('Outside the registered vault', policy)
                for name in ['jd-vault-research', 'jd-vault-journal']:
                    text = (self.home/skills/name/'SKILL.md').read_text()
                    self.assertTrue(text.startswith('---\n'))
                    self.assertNotIn('{{POLICY}}', text)
                self.assertFalse((self.home/skills/'librarian-vault-manager').exists())
                self.assertEqual(len(list((self.repo/f'.{harness}/agents').iterdir())), 8)
                before = (self.home/rules).read_bytes()
                self.setup(harness)
                self.assertEqual(before, (self.home/rules).read_bytes())
                diagnostic = self.run_cmd('python3', str(self.repo/'scripts/doctor.py'), '--harness', harness)
                self.assertIn('Configuration checks passed', diagnostic.stdout)
        vault = self.repo/'vaults/my-notes'
        self.assertTrue((vault/'AGNT/00-IDX/AGNT.00.00.md').exists())
        self.assertTrue((vault/'JRNL/AGNT').is_dir())
        self.assertEqual(json.loads((vault/'.obsidian/daily-notes.json').read_text())['folder'], 'JRNL')
        registry = json.loads((self.home/'.config/jd-vault/vaults.json').read_text())
        self.assertEqual(len(registry['vaults']), 1)
        config = json.loads((self.home/'.config/opencode/opencode.json').read_text())
        self.assertEqual(config['mcp']['obsidian-vault-mcp']['command'], ['npx', '-y', '@jabez007/obsidian-vault-mcp@2.1.0'])
        claude_installs = [c for c in self.calls() if c['cli']=='claude' and c['args'][:2]==['plugin','install']]
        self.assertTrue(all(c['args'][-2:] == ['--scope', 'user'] for c in claude_installs))

    def test_preserves_other_vault_until_explicit_selection(self):
        path = self.home/'.obsidian-mcp.config.json'
        previous = json.dumps({'vault_path': str(self.other/'vault'), 'workspace_path': str(self.other)})
        path.write_text(previous)
        for harness in ['claude', 'codex', 'gemini', 'opencode']:
            result = self.setup(harness, ok=False)
            self.assertIn('existing selection was preserved', result.stdout)
            self.assertEqual(path.read_text(), previous)
        self.assertEqual(self.calls(), [])
        self.setup('opencode', '--vault', 'mine', '--skip-index')
        self.assertEqual(json.loads(path.read_text())['vault_path'], str(self.repo/'vaults/mine'))

    def test_check_mode_never_installs_or_changes_selection(self):
        for harness in ['claude', 'codex', 'gemini', 'opencode']:
            self.setup(harness, '--vault', 'mine', '--check')
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.home/'.obsidian-mcp.config.json').exists())
        self.assertFalse((self.repo/'vaults').exists())

    def test_merge_keeps_user_settings_comments_and_instructions(self):
        base = self.home/'.config/opencode'
        base.mkdir(parents=True)
        settings = base/'opencode.jsonc'
        settings.write_text('''{
  // Keep the user's model, trailing commas, and unrelated server.
  "model": "provider/model",
  "mcp": {"other": {"type": "remote", "url": "https://example.invalid/mcp"},},
  "permission": {"bash": "ask"},
}
''')
        rules = base/'AGENTS.md'
        rules.write_text('User instructions must stay.\n')
        self.setup('opencode', '--vault', 'mine', '--skip-index')
        data = json.loads(installer.masked_jsonc(settings.read_text()))
        self.assertEqual(data['model'], 'provider/model')
        self.assertEqual(data['mcp']['other']['url'], 'https://example.invalid/mcp')
        self.assertIn('// Keep the user', settings.read_text())
        self.assertTrue(rules.read_text().startswith('User instructions must stay.\n'))
        before = settings.read_text()
        self.setup('opencode', '--skip-index')
        self.assertEqual(settings.read_text(), before)

    def test_codex_uses_existing_global_override(self):
        directory = self.home/'.codex'
        directory.mkdir()
        override = directory/'AGENTS.override.md'
        override.write_text('Existing override.\n')
        self.setup('codex', '--vault', 'mine', '--skip-index')
        self.assertIn('BEGIN JD-VAULT', override.read_text())
        self.assertFalse((directory/'AGENTS.md').exists())

    def test_codex_preserves_an_enabled_plugin(self):
        self.setup('codex', '--vault', 'mine', '--skip-index', extra={'SETUP_EXISTING_PLUGIN': '1'})
        actions = [c['args'][:2] for c in self.calls() if c['cli'] == 'codex']
        self.assertNotIn(['plugin', 'remove'], actions)
        self.assertNotIn(['plugin', 'add'], actions)

    def test_gemini_retires_only_old_template_hook(self):
        directory = self.home/'.gemini'
        directory.mkdir()
        settings = directory/'settings.json'
        settings.write_text(json.dumps({'context': {'fileName': 'CUSTOM.md'}, 'hooks': {'SessionStart': [
            {'matcher': '*', 'hooks': [{'name': 'agent-memory-boot', 'command': '/old/template/hook'},
                                       {'name': 'keep-me', 'command': '/custom/hook'}]}, {'matcher': 'resume'}]}}))
        self.setup('gemini', '--vault', 'mine', '--skip-index')
        data = json.loads(settings.read_text())
        self.assertEqual(data['context']['fileName'], ['CUSTOM.md', 'GEMINI.md'])
        self.assertEqual(data['hooks']['SessionStart'][0]['hooks'], [{'name': 'keep-me', 'command': '/custom/hook'}])
        self.assertEqual(data['hooks']['SessionStart'][1], {'matcher': 'resume'})

    def test_unowned_skill_and_malformed_settings_fail_before_installation(self):
        target = self.home/'.config/opencode/skills/jd-vault-research/SKILL.md'
        target.parent.mkdir(parents=True)
        target.write_text('User skill')
        self.assertIn('unowned skill', self.setup('opencode', '--vault', 'mine', ok=False).stdout)
        self.assertEqual(self.calls(), [])
        target.unlink()
        (self.home/'.config/opencode/opencode.json').write_text('{broken')
        self.setup('opencode', '--vault', 'mine', ok=False)
        self.assertEqual(self.calls(), [])

    def test_index_failure_and_empty_retrieval_do_not_report_success(self):
        for extra in [{'SETUP_FAIL_INDEX': '1'}, {'SETUP_EMPTY_QUERY': '1'}]:
            result = self.setup('opencode', '--vault', 'mine', ok=False, extra=extra)
            self.assertNotIn('Setup complete.', result.stdout)
            self.assertFalse((self.home/'.config/opencode/AGENTS.md').exists())
        result = self.setup('opencode', '--skip-index')
        self.assertIn('Semantic search readiness was not checked', result.stdout)

    def test_failed_initialization_resumes_without_overwriting(self):
        self.setup('opencode', '--vault', 'mine', '--skip-index', ok=False,
                   extra={'SETUP_FAIL_CREATE': 'AGNT/00-IDX/AGNT.00.00.md'})
        note = self.repo/'vaults/mine/00.00.md'
        note.write_text('Preserve this user edit during retry.\n')
        self.setup('opencode', '--skip-index')
        self.assertEqual(note.read_text(), 'Preserve this user edit during retry.\n')
        self.assertTrue((self.repo/'vaults/mine/AGNT/00-IDX/AGNT.00.00.md').exists())
        self.assertFalse((self.repo/'vaults/mine/.jd-vault-initializing').exists())

    def test_local_memory_hook_does_not_promote_another_vault(self):
        self.setup('opencode', '--vault', 'mine', '--skip-index')
        local = self.run_cmd('bash', str(self.repo/'scripts/agent-memory-context.sh')).stdout
        self.assertIn('Agent Memory SOPs', local)
        (self.home/'.obsidian-mcp.config.json').write_text(json.dumps({'vault_path': str(self.other), 'workspace_path': str(self.other)}))
        foreign = self.run_cmd('bash', str(self.repo/'scripts/agent-memory-context.sh')).stdout
        self.assertNotIn('New AGNT rules go', foreign)
        self.assertIn('another repository', foreign)

    def test_doctor_reports_missing_install_and_unknown_vault(self):
        self.setup('opencode', '--vault', 'mine', '--skip-index')
        (self.home/'.config/opencode/skills/jd-vault-research/SKILL.md').unlink()
        (self.home/'.obsidian-mcp.config.json').write_text(json.dumps({'vault_path': str(self.other)}))
        result = self.run_cmd('python3', str(self.repo/'scripts/doctor.py'), '--harness', 'opencode', '--skip-query', ok=False)
        self.assertIn('Missing', result.stdout)
        self.assertIn('not registered', result.stdout)

    @unittest.skipUnless(os.environ.get('MCP_SETUP_RELEASE'), 'Set MCP_SETUP_RELEASE for real MCP provisioning and retrieval')
    def test_published_mcp_provisions_exact_starter_content(self):
        release = Path(os.environ['MCP_SETUP_RELEASE'])
        command = shlex.join(['node', str(release/'dist/index.js')])
        result = self.setup('opencode', '--vault', 'real-vault', extra={'MCP_CMD': command})
        self.assertIn('Semantic retrieval returned a note', result.stdout)
        for relative in ['00.00.md', 'AGNT/00-IDX/AGNT.00.00.md', '_SYS/TMPL/Daily.md']:
            self.assertEqual((self.repo/'vaults/real-vault'/relative).read_bytes(),
                             (SOURCE/'references/vault-starter'/relative).read_bytes())
        self.run_cmd('python3', str(self.repo/'scripts/doctor.py'), '--harness', 'opencode',
                     extra={'MCP_CMD': command})


class JsoncTest(unittest.TestCase):
    def test_insertion_preserves_strings_comments_and_siblings(self):
        for text in ['{}', '{/* x, } */}', '{"a": "comma, } // text"}', '{"a": 1, // x\n}', '{"a": 1 /* comma, } */}']:
            with self.subTest(text=text):
                result = installer.jsonc_set(text, ['mcp', 'vault'], {'enabled': True})
                expected = json.loads(installer.masked_jsonc(text)) | {'mcp': {'vault': {'enabled': True}}}
                self.assertEqual(json.loads(installer.masked_jsonc(result)), expected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
