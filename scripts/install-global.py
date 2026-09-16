#!/usr/bin/env python3
"""Install template-owned global policy and skills without changing the MCP."""

import argparse
import json
import os
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parent.parent
START = '<!-- BEGIN JD-VAULT TEMPLATE -->'
END = '<!-- END JD-VAULT TEMPLATE -->'
OWNER = '<!-- Installed by johnny-decimal-zettelkasten; rerun setup to update. -->'
PACKAGE = '@jabez007/obsidian-vault-mcp@2.1.0'


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Follow an existing user symlink rather than replacing it.
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(content)
    try:
        if path.exists():
            temporary.chmod(path.stat().st_mode & 0o777)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def load_json(path, default):
    return json.loads(path.read_text()) if path.exists() else default


def masked_jsonc(text):
    """Blank comments and trailing commas, retaining offsets for surgical edits."""
    pattern = r'"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/'
    def mask(match):
        value = match.group()
        return value if value.startswith('"') else re.sub(r'[^\r\n]', ' ', value)
    clean = re.sub(pattern, mask, text)
    # Strings must also be skipped when finding trailing commas.
    clean = re.sub(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])',
                   lambda m: ' ' if m.group() == ',' else m.group(), clean)
    json.loads(clean)
    return clean


def jsonc_set(text, keys, value):
    """Replace one nested object member while preserving surrounding comments."""
    clean = masked_jsonc(text)
    decoder = json.JSONDecoder()
    data = json.loads(clean)
    if not isinstance(data, dict):
        raise ValueError('Expected a JSON object')
    i = clean.index('{') + 1
    last_end = i
    while True:
        while clean[i].isspace() or clean[i] == ',':
            i += 1
        if clean[i] == '}':
            close = i
            break
        key, end = decoder.raw_decode(clean, i)
        i = end
        while clean[i].isspace():
            i += 1
        if clean[i] != ':':
            raise ValueError('Expected a JSON property')
        i += 1
        while clean[i].isspace():
            i += 1
        start = i
        _, end = decoder.raw_decode(clean, start)
        if key == keys[0]:
            replacement = (json.dumps(value, indent=2) if len(keys) == 1
                           else jsonc_set(text[start:end], keys[1:], value))
            return text[:start] + replacement + text[end:]
        last_end = end
        i = end
    nested = value
    for key in reversed(keys[1:]):
        nested = {key: nested}
    # A trailing comma is blanked in clean but retained in text.
    trailing = ',' in masked_comments(text[last_end:close])
    comma = ',' if data and not trailing else ''
    insertion = '\n  ' + json.dumps(keys[0]) + ': ' + json.dumps(nested, indent=2) + '\n'
    return text[:last_end] + comma + text[last_end:close] + insertion + text[close:]


def masked_comments(text):
    return re.sub(r'//[^\r\n]*|/\*[\s\S]*?\*/', '', text)


def managed_block(path, body):
    current = path.read_text() if path.exists() else ''
    block = START + '\n' + body.rstrip() + '\n' + END
    if START in current or END in current:
        if current.count(START) != 1 or current.count(END) != 1 or current.index(START) > current.index(END):
            raise ValueError(f'Malformed managed block in {path}; repair its markers before setup')
        first, rest = current.split(START, 1)
        _, last = rest.split(END, 1)
        return first + block + last
    return current + ('\n\n' if current else '') + block + '\n'


def locations(harness):
    home = Path.home()
    config = Path(os.environ.get('XDG_CONFIG_HOME', home / '.config'))
    if harness == 'codex':
        base = Path(os.environ.get('CODEX_HOME', home / '.codex'))
        override = base / 'AGENTS.override.md'
        instructions = override if override.exists() and override.read_text().strip() else base / 'AGENTS.md'
        return instructions, home / '.agents/skills', None
    if harness == 'claude':
        base = Path(os.environ.get('CLAUDE_CONFIG_DIR', home / '.claude'))
        return base / 'CLAUDE.md', base / 'skills', None
    if harness == 'gemini':
        return home / '.gemini/GEMINI.md', home / '.gemini/skills', home / '.gemini/settings.json'
    base = config / 'opencode'
    settings = base / 'opencode.jsonc' if (base / 'opencode.jsonc').exists() else base / 'opencode.json'
    return base / 'AGENTS.md', base / 'skills', settings


def plan(harness):
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    registry_path = config / 'jd-vault/vaults.json'
    registry = load_json(registry_path, {'version': 1, 'vaults': []})
    if registry.get('version') != 1 or not isinstance(registry.get('vaults'), list):
        raise ValueError(f'Unsupported vault registry: {registry_path}')
    policy = (ROOT / 'references/global-vault/instructions.md').read_text().replace('{{REGISTRY_PATH}}', str(registry_path))
    instructions, skills, settings = locations(harness)
    writes = {instructions: managed_block(instructions, policy)}
    for source in sorted((ROOT / 'references/global-vault/skills').glob('*/SKILL.md')):
        target = skills / source.parent.name / 'SKILL.md'
        if target.exists() and OWNER not in target.read_text():
            raise ValueError(f'Refusing to replace an unowned skill: {target}')
        body = source.read_text().replace('{{POLICY}}', policy)
        # Ownership marker goes after frontmatter to preserve skill discovery.
        first, frontmatter, rest = body.split('---', 2)
        writes[target] = first + '---' + frontmatter + '---\n\n' + OWNER + rest
    if settings:
        raw = settings.read_text() if settings.exists() else '{}\n'
        data = json.loads(masked_jsonc(raw))
        if harness == 'opencode':
            server = {'type': 'local', 'command': ['npx', '-y', PACKAGE], 'enabled': True, 'timeout': 30000}
            raw = jsonc_set(raw, ['mcp', 'obsidian-vault-mcp'], server)
        else:
            # Ensure the global policy is loaded even with custom context filenames.
            names = data.get('context', {}).get('fileName', ['GEMINI.md'])
            names = [names] if isinstance(names, str) else names
            if 'GEMINI.md' not in names:
                raw = jsonc_set(raw, ['context', 'fileName'], names + ['GEMINI.md'])
            # Retire only the old template hook, whose global SOPs promoted rules.
            sessions = data.get('hooks', {}).get('SessionStart', [])
            if any(h.get('name') == 'agent-memory-boot' for group in sessions for h in group.get('hooks', [])):
                kept = []
                for group in sessions:
                    entry = dict(group)
                    if 'hooks' in entry:
                        entry['hooks'] = [h for h in entry['hooks'] if h.get('name') != 'agent-memory-boot']
                        if not entry['hooks']:
                            continue
                    kept.append(entry)
                raw = jsonc_set(raw, ['hooks', 'SessionStart'], kept)
        writes[settings] = raw
    return registry_path, registry, writes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--harness', choices=['claude', 'codex', 'gemini', 'opencode'], required=True)
    parser.add_argument('--check', action='store_true', help='Validate destinations without writing')
    args = parser.parse_args()
    registry_path, registry, writes = plan(args.harness)
    if args.check:
        print(f'Global {args.harness} destinations validated.')
        return
    selected = load_json(ROOT / '.jd-vault-local.json', {})
    if not selected.get('vault_path'):
        raise ValueError('Run scripts/configure-vault.sh before installing global instructions')
    registry['vaults'] = [v for v in registry['vaults'] if v['vault_path'] != selected['vault_path']]
    registry['vaults'].append(selected)
    writes[registry_path] = json.dumps(registry, indent=2) + '\n'
    for path, content in writes.items():
        atomic_write(path, content)
    print(f'Installed global {args.harness} research, journal capture, and template policy.')
    print('Management skills and agents remain in the vault repository. Restart the harness to load changes.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(f'Global setup: {error}') from error
