#!/usr/bin/env python3
"""Check global template installation and the MCP's selected vault."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('installer', ROOT / 'scripts/install-global.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--harness', choices=['claude', 'codex', 'gemini', 'opencode'], required=True)
    parser.add_argument('--skip-query', action='store_true', help='Check configuration without testing semantic retrieval')
    args = parser.parse_args()
    errors = []
    registry_path, registry, _ = installer.plan(args.harness)
    rules, skills, settings = installer.locations(args.harness)
    for path in [rules, skills/'jd-vault-research/SKILL.md', skills/'jd-vault-journal/SKILL.md']:
        if not path.exists():
            errors.append(f'Missing {path}')
    if rules.exists() and installer.START not in rules.read_text():
        errors.append(f'Template instructions are missing from {rules}')
    if args.harness == 'opencode':
        data = json.loads(installer.masked_jsonc(settings.read_text())) if settings.exists() else {}
        server = data.get('mcp', {}).get('obsidian-vault-mcp', {})
        if not server or server.get('enabled') is False:
            errors.append(f'Global MCP registration is missing or disabled in {settings}')
    command = shlex.split(os.environ.get('MCP_CMD', f'npx -y {installer.PACKAGE}'))

    def mcp(*arguments):
        result = subprocess.run(command + list(arguments), capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise ValueError(f'MCP CLI failed ({result.returncode}); run the command directly for diagnostics')
        return result.stdout.strip()

    current = json.loads(mcp('obsidian_get_config'))
    matching = [v for v in registry['vaults'] if v['vault_path'] == current.get('vault_path')]
    if not matching:
        errors.append(f'The selected vault is not registered in {registry_path}')
    elif matching[0]['workspace_path'] != current.get('workspace_path') or matching[0]['vault_id'] != current.get('vault_id'):
        errors.append('The selected workspace or vault ID differs from the template registration; rerun setup')
    print(f"Selected vault: {current.get('vault_path') or 'none'}")
    print(f'Global instructions: {rules}')
    print('Workflow: research across systems; capture under JRNL; manage permanent notes from the owning repository.')
    print('This is template guidance. The MCP is unchanged and does not enforce that workflow.')
    if args.skip_query:
        print('Semantic retrieval was not checked (--skip-query).')
    elif 'File:' not in mcp('obsidian_rag_query', '--query', 'Vault Index', '--limit', '1'):
        errors.append('Semantic search returned no note; index the selected vault and retry')
    else:
        print('Semantic retrieval returned a note.')
    if errors:
        for error in errors:
            print(f'FAIL: {error}')
        return 1
    print('Configuration checks passed. Restart the harness and verify its loaded tools and skills; this command does not run a model session.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.TimeoutExpired, KeyError, TypeError) as error:
        raise SystemExit(f'Doctor: {error}') from error
