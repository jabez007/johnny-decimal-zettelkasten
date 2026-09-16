#!/usr/bin/env python3
"""Select a vault, initialize new vaults, and verify semantic search readiness."""

import argparse
import json
import os
from pathlib import Path
import queue
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading


class McpClient:
    """Use structured tool arguments; CLI flags cannot carry leading '---'."""

    def __init__(self, command, env):
        self.process = subprocess.Popen(command, env=env, cwd=ROOT, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, text=True, start_new_session=True)
        self.responses = queue.Queue()
        self.sequence = 0
        def receive():
            for line in self.process.stdout:
                try:
                    self.responses.put(json.loads(line))
                except json.JSONDecodeError:
                    continue
            self.responses.put(None)
        self.reader = threading.Thread(target=receive, daemon=True)
        self.reader.start()

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + '\n')
        self.process.stdin.flush()

    def request(self, method, params):
        self.sequence += 1
        self.send({'jsonrpc': '2.0', 'id': self.sequence, 'method': method, 'params': params})
        while True:
            message = self.responses.get(timeout=300)
            if message is None:
                raise ValueError('MCP server exited before responding')
            if message.get('id') != self.sequence:
                continue
            if 'error' in message:
                raise ValueError(f'MCP request failed: {message["error"]}')
            result = message['result']
            if result.get('isError'):
                raise ValueError(f'MCP tool failed: {result.get("content")}')
            return result

    def close(self):
        self.process.stdin.close()
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()
        self.reader.join(timeout=5)
        self.process.stdout.close()

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = '@jabez007/obsidian-vault-mcp@2.1.0'


def read_config():
    for name in ['.obsidian-mcp.config.json', '.gemini-obsidian.config.json']:
        path = Path.home() / name
        if path.exists():
            return json.loads(path.read_text())
    return {}


def run(*args, capture=False, env=None):
    result = subprocess.run(args, cwd=ROOT, env=env, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vault', metavar='NAME', help='Select vaults/NAME explicitly; switches the global MCP default')
    indexing = parser.add_mutually_exclusive_group()
    indexing.add_argument('--index', action='store_true', help='Index and verify retrieval (the default)')
    indexing.add_argument('--skip-index', action='store_true', help='Defer indexing and the retrieval check')
    parser.add_argument('--check', action='store_true', help='Validate selection without changing files')
    args = parser.parse_args()
    config = read_config()
    raw = args.vault
    if raw is None:
        existing = config.get('vault_path')
        if existing:
            selected = Path(existing).resolve()
            if selected.parent == (ROOT / 'vaults').resolve():
                raw = selected.name
            elif not sys.stdin.isatty() or args.check:
                raise ValueError('A vault in another repository is already selected. Use --vault NAME to explicitly select this checkout; the existing selection was preserved.')
        if raw is None:
            raw = input('Enter Obsidian vault name [example]: ').strip() if sys.stdin.isatty() and not args.check else ''
            raw = raw or 'example'
    slug = re.sub('[^a-z0-9]+', '-', raw.lower()).strip('-')
    if not slug:
        raise ValueError('Vault name must contain at least one letter or digit')
    vault = ROOT / 'vaults' / slug
    if vault.resolve().parent != (ROOT / 'vaults').resolve():
        raise ValueError('The vault must be a direct directory under this checkout\'s vaults/')
    if args.check:
        print(f'Vault selection validated: {vault}')
        return
    fresh = not vault.exists() or (vault.is_dir() and not any(vault.iterdir()))
    vault.mkdir(parents=True, exist_ok=True)
    initializing = vault / '.jd-vault-initializing'
    if fresh:
        initializing.touch()
    command = shlex.split(os.environ.get('MCP_CMD', f'npx -y {PACKAGE}'))
    if not command:
        raise ValueError('MCP_CMD must name a command')
    repo_slug = re.sub('[^a-z0-9]+', '-', ROOT.name.lower()).strip('-') or 'vault'
    vault_id = run('node', str(ROOT / 'scripts/index-snapshots.mjs'), 'register',
                   '--vault', str(vault), '--id', f'{repo_slug}_{slug}', capture=True)
    env = os.environ | {'OBSIDIAN_VAULT_PATH': str(vault),
                        'OBSIDIAN_WORKSPACE_PATH': str(ROOT), 'OBSIDIAN_VAULT_ID': vault_id}

    def mcp(operation, *arguments):
        output = run(*command, operation, *arguments, capture=True, env=env)
        try:
            result = json.loads(output)
        except json.JSONDecodeError:
            result = None
        if isinstance(result, dict) and (result.get('success') is False or result.get('isError') is True):
            raise ValueError(f'{operation} failed: {output}')
        return output

    mcp('obsidian_set_vault', '--path', str(vault), '--workspace_path', str(ROOT), '--vault_id', vault_id)
    if initializing.exists():
        starter = ROOT / 'references/vault-starter'
        client = McpClient(command, env)
        try:
            client.request('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {},
                                         'clientInfo': {'name': 'jd-vault-setup', 'version': '1'}})
            client.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            for source in sorted(starter.rglob('*')):
                if not source.is_file():
                    continue
                relative = source.relative_to(starter)
                if (vault / relative).exists():
                    continue
                if source.suffix == '.md':
                    client.request('tools/call', {'name': 'obsidian_create_note', 'arguments': {
                        'file_path': str(relative), 'content': source.read_text(),
                        'vault_path': str(vault), 'workspace_path': str(ROOT), 'vault_id': vault_id}})
                else:
                    target = vault / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, target)
        finally:
            client.close()
        (vault / 'JRNL/AGNT').mkdir(parents=True, exist_ok=True)
        initializing.unlink()
    run('bash', str(ROOT / 'scripts/configure-index-git.sh'))
    daily_path = vault / '.obsidian/daily-notes.json'
    daily = json.loads(daily_path.read_text()) if daily_path.exists() else {}
    selected = {'vault_path': str(vault), 'workspace_path': str(ROOT), 'vault_id': vault_id,
                'daily_notes_folder': daily.get('folder', ''), 'harness_policy': 'jd-vault-v1'}
    local = ROOT / '.jd-vault-local.json'
    temporary = local.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(selected, indent=2) + '\n')
    temporary.replace(local)
    if args.skip_index:
        print('Indexing deferred (--skip-index). Semantic search readiness was not checked.')
    else:
        print('Indexing the selected vault and checking semantic retrieval...', flush=True)
        common = ['--vault_path', str(vault), '--workspace_path', str(ROOT), '--vault_id', vault_id]
        mcp('obsidian_rag_index', *common)
        result = mcp('obsidian_rag_query', '--query', 'Vault Index', '--limit', '1', *common)
        if 'File:' not in result:
            raise ValueError('Semantic retrieval returned no note. Setup is incomplete; check indexing or add a note and rerun.')
        print('Semantic retrieval returned a note.')
    print(f'Vault configured: {vault} (id: {vault_id})')
    if not (selected['daily_notes_folder'] == 'JRNL' or selected['daily_notes_folder'].startswith('JRNL/')):
        print('Daily notes are not configured under JRNL. Global capture will use dated JRNL notes until you configure the daily-note folder locally.')
    print('Restart existing MCP sessions to load the selected vault.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, queue.Empty) as error:
        raise SystemExit(f'Vault setup: {error}') from error
