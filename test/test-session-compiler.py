#!/usr/bin/env python3
"""Exercise transcript selection and reviewer invocation without a model call."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RECENT = '2099-01-02T12:00:00Z'


class CompilerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='jd-compiler-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.home.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), AI_MEMORY_DRY_RUN='dump', TZ='UTC',
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        for key in ['CODEX_HOME', 'CLAUDE_CONFIG_DIR', 'XDG_DATA_HOME', 'OPENCODE_DB']:
            self.env.pop(key, None)

    def write_log(self, path, records):
        target = self.home / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(records) if isinstance(records, dict)
                          else '\n'.join(json.dumps(row) for row in records) + '\n')
        return target

    def compile(self, *args, extra=None, cwd=None, wrapper=False):
        script = ROOT / ('.gemini/skills/librarian-vault-manager/scripts/compile-sessions.sh'
                         if wrapper else 'scripts/compile-sessions.sh')
        return subprocess.run(['bash', str(script), *args], cwd=cwd or ROOT,
                              env=self.env | (extra or {}), capture_output=True, text=True)

    def claude_log(self):
        return self.write_log('.claude/projects/example/session.jsonl', [
            {'type': 'user', 'cwd': '/projects/example', 'sessionId': 'claude-session',
             'timestamp': RECENT, 'message': {'content': 'prefer pytest here'}},
            {'type': 'assistant', 'timestamp': RECENT,
             'message': {'content': [{'type': 'text', 'text': 'assistant suggestion'}]}},
            {'type': 'user', 'timestamp': RECENT,
             'message': {'content': [{'type': 'text', 'text': 'user text block'},
                                     {'type': 'image', 'source': 'ignored image'}]}},
            {'type': 'user', 'timestamp': RECENT,
             'message': {'content': [{'type': 'tool_result', 'content': 'noise marker'}]}}])

    def test_legacy_gemini_and_jsonl_keep_source_and_scope(self):
        self.write_log('.gemini/tmp/project/chats/legacy.json', {
            'sessionId': 'legacy-session', 'projectHash': 'project-hash',
            'directories': ['/projects/gemini'], 'messages': [
                {'type': 'user', 'timestamp': RECENT, 'content': 'legacy marker'}]})
        self.write_log('.gemini/tmp/project/chats/current.jsonl', [
            {'sessionId': 'jsonl-session', 'projectHash': 'project-hash',
             'directories': ['/projects/gemini']},
            {'type': 'gemini', 'timestamp': RECENT,
             'content': [{'text': 'jsonl marker'}]}])
        result = self.compile('2099-01-01', '2099-01-03')
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ['legacy marker', 'jsonl marker', 'legacy-session',
                     'jsonl-session', '/projects/gemini', '2099-01-02', 'legacy.json']:
            self.assertIn(text, result.stdout)

    def test_filters_turn_dates_in_a_resumed_transcript(self):
        self.write_log('.codex/sessions/session.jsonl', [
            {'type': 'session_meta', 'payload': {'id': 'codex-session', 'cwd': '/projects/codex'}},
            {'type': 'response_item', 'timestamp': '2001-01-01T00:00:00Z',
             'payload': {'type': 'message', 'role': 'user',
                         'content': [{'type': 'input_text', 'text': 'old marker'}]}},
            {'type': 'event_msg', 'timestamp': RECENT,
             'payload': {'type': 'agent_message', 'message': 'new marker'}},
            {'type': 'event_msg', 'timestamp': '2099-01-04T00:00:00Z',
             'payload': {'type': 'agent_message', 'message': 'outside marker'}}])
        result = self.compile('2099-01-01', '2099-01-03')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('old marker', result.stdout)
        self.assertNotIn('outside marker', result.stdout)
        for text in ['new marker', 'codex-session', '/projects/codex']:
            self.assertIn(text, result.stdout)

    def test_gemini_rewinds_updates_and_project_registry(self):
        self.write_log('.gemini/projects.json', {'projects': {'/projects/registered': 'registered-slug'}})
        self.write_log('.gemini/tmp/registered-slug/chats/session.jsonl', [
            {'sessionId': 'mutated-session', 'projectHash': 'hash'},
            {'id': 'u1', 'type': 'user', 'timestamp': RECENT, 'content': 'kept decision'},
            {'id': 'a1', 'type': 'gemini', 'timestamp': RECENT, 'content': 'abandoned answer'},
            {'id': 'u2', 'type': 'user', 'timestamp': RECENT, 'content': 'abandoned decision'},
            {'$rewindTo': 'a1'},
            {'id': 'a2', 'type': 'gemini', 'timestamp': RECENT, 'content': 'initial answer'},
            {'id': 'a2', 'type': 'gemini', 'timestamp': RECENT, 'content': 'updated answer'},
            {'$set': {'summary': 'not a message'}}])
        result = self.compile('2099-01-01')
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ['kept decision', 'updated answer', '/projects/registered']:
            self.assertIn(text, result.stdout)
        for text in ['abandoned answer', 'abandoned decision', 'initial answer', 'not a message']:
            self.assertNotIn(text, result.stdout)

    def test_empty_logs_and_unknown_host(self):
        result = self.compile('2099-01-01')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('No session logs found', result.stdout)
        self.claude_log()
        result = self.compile('2099-01-01', extra={'AI_MEMORY_HOST': 'bogus', 'AI_MEMORY_DRY_RUN': ''})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unsupported AI_MEMORY_HOST', result.stderr)

    def test_reviewer_failure_is_propagated(self):
        self.claude_log()
        host = self.bin / 'claude'
        host.write_text('#!/bin/sh\nexit 23\n')
        host.chmod(0o755)
        result = self.compile('2099-01-01', extra={'AI_MEMORY_HOST': 'claude', 'AI_MEMORY_DRY_RUN': ''})
        self.assertEqual(result.returncode, 23)

    def test_unknown_timestamps_do_not_fall_back_to_file_mtime(self):
        self.write_log('.claude/projects/example/unknown.jsonl', [
            {'type': 'user', 'message': {'content': 'undated marker'}}])
        result = self.compile('1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('No session logs found', result.stdout)
        self.assertNotIn('undated marker', result.stdout)
        self.assertIn('timestamp', result.stderr.lower())

    def test_claude_roles_and_noise(self):
        self.claude_log()
        result = self.compile('2099-01-01')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('[user] prefer pytest here', result.stdout)
        self.assertIn('[assistant] assistant suggestion', result.stdout)
        self.assertIn('[user] user text block', result.stdout)
        self.assertNotIn('noise marker', result.stdout)
        self.assertIn('/projects/example', result.stdout)

    def test_opencode_retains_session_and_project(self):
        db = self.home / '.local/share/opencode/opencode.db'
        db.parent.mkdir(parents=True)
        with sqlite3.connect(db) as conn:
            conn.executescript('''
                CREATE TABLE session(id TEXT, directory TEXT);
                CREATE TABLE message(id TEXT, session_id TEXT, time_created INTEGER, data TEXT);
                CREATE TABLE part(message_id TEXT, time_created INTEGER, data TEXT);
                INSERT INTO session VALUES ('oc-session', '/projects/opencode');
                INSERT INTO message VALUES ('m1', 'oc-session', 4071038400000, '{"role":"user"}');
                INSERT INTO part VALUES ('m1', 4071038400000, '{"type":"text","text":"sqlite marker"}');
            ''')
        result = self.compile('2099-01-01', '2099-01-03')
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ['sqlite marker', '/projects/opencode', 'oc-session']:
            self.assertIn(text, result.stdout)

    def test_reviewer_commands_are_proposal_only_and_use_template_cwd(self):
        self.claude_log()
        call_path = self.base / 'call.json'
        fixture = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path(os.environ['REVIEW_CALL']).write_text(json.dumps({
    'args': sys.argv[1:], 'cwd': os.getcwd(), 'stdin': sys.stdin.read(),
    'attachment': Path(sys.argv[sys.argv.index('--file') + 1]).read_text()
                  if '--file' in sys.argv else ''}))
'''
        for host in ['gemini', 'codex', 'claude', 'opencode']:
            exe = self.bin / host
            exe.write_text(fixture)
            exe.chmod(0o755)
            result = self.compile('2099-01-01', extra={
                'AI_MEMORY_DRY_RUN': '', 'AI_MEMORY_HOST': host, 'REVIEW_CALL': str(call_path)},
                cwd=self.base, wrapper=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            call = json.loads(call_path.read_text())
            self.assertEqual(call['cwd'], str(ROOT))
            args = call['args']
            prompt = '\n'.join(args)
            self.assertIn('proposal', prompt.lower())
            self.assertIn('Do not write', prompt)
            self.assertIn('daily-reviewer', prompt)
            for forbidden in ['--policy', 'yolo', '--ask-for-approval',
                              '--dangerously-bypass-hook-trust', 'acceptEdits']:
                self.assertNotIn(forbidden, args)
            if host == 'codex':
                self.assertEqual(args[args.index('--sandbox') + 1], 'read-only')
            if host == 'opencode':
                self.assertIn('--file', args)
                self.assertEqual(len(args) - args.index('--file'), 2)
                self.assertIn('prefer pytest here', call['attachment'])
                self.assertIn('/projects/example', call['attachment'])
            else:
                self.assertIn('prefer pytest here', call['stdin'])

    def test_invalid_range_fails_without_a_reviewer_call(self):
        result = self.compile('2099-01-03', '2099-01-01')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('date', result.stderr.lower())


if __name__ == '__main__':
    unittest.main(verbosity=2)
