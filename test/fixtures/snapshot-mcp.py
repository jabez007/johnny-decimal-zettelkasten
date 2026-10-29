#!/usr/bin/env python3
"""Small protocol fixture. Real database compatibility is tested separately."""
import hashlib
import json
import os
from pathlib import Path
import sys

if sys.argv[1] == 'obsidian_set_vault':
    raise SystemExit(0)
args, rest = {}, sys.argv[2:]
while rest:
    key = rest.pop(0)
    if '=' in key:
        key, value = key.split('=', 1)
    else:
        value = rest.pop(0)
    args[key] = value
vault = Path(args['--vault_path'])
workspace = Path(args['--workspace_path'])
vault_id = args['--vault_id']
if log := os.environ.get('SNAPSHOT_FIXTURE_LOG'):
    with open(log, 'a') as f:
        f.write(json.dumps({'operation': sys.argv[1], 'vault': vault_id, 'rules_text': args.get('--rules_text')}) + '\n')
if sys.argv[1] == 'obsidian_rag_index':
    if os.environ.get('SNAPSHOT_FIXTURE_INDEX_FAIL_ID') == vault_id:
        print(json.dumps({'success': False, 'message': 'fixture indexing failed'}))
    else:
        print(json.dumps({'success': True, 'chunks': 0}))
    raise SystemExit(0)
if os.environ.get('SNAPSHOT_FIXTURE_FAIL_ID') == vault_id:
    print('fixture: snapshot preparation failed', file=sys.stderr)
    raise SystemExit(1)
# Ignore rules are exact note paths here; the real MCP uses gitignore syntax.
rules_file = vault / '.obsidian-mcpignore'
rules = rules_file.read_text() if rules_file.exists() else ''
if '--rules_text' in args and args['--rules_text'] != rules:
    print('fixture: supplied ignore rules differ from the current index rules', file=sys.stderr)
    raise SystemExit(1)
ignored = {line.strip() for line in rules.splitlines() if line.strip()}
rules_fingerprint = hashlib.sha256(rules.encode()).hexdigest()
hashes = {str(p.relative_to(vault)): hashlib.md5(p.read_bytes()).hexdigest()
          for p in vault.rglob('*.md')
          if not any(s.startswith('.') for s in p.relative_to(vault).parts) and str(p.relative_to(vault)) not in ignored}
fingerprint = hashlib.sha256(json.dumps([rules_fingerprint, hashes], sort_keys=True).encode()).hexdigest()
target = workspace / '.obsidian-vault-mcp/vaults' / vault_id / 'snapshots' / fingerprint
reused = target.exists()
target.mkdir(parents=True, exist_ok=True)
payload = {
    f'lancedb/notes.lance/data/{fingerprint}.lance': json.dumps(hashes).encode(),
    'lancedb/notes.lance/_versions/1.manifest': b'fixture manifest',
    'file-hashes.json': json.dumps(hashes).encode(),
    'schema-version.json': b'{"notesTableSchemaVersion":3}',
    'index-metadata.json': json.dumps({'fileCount': len(hashes), 'latestMtimeMs': 1, 'indexedAt': 1}).encode(),
}
files = []
for name, data in payload.items():
    file = target / name
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_bytes(data)
    files.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
result = {
    'success': True, 'snapshotPath': str(target), 'rulesFingerprint': rules_fingerprint, 'sourceFingerprint': fingerprint,
    'sourceVersion': 1, 'reused': reused,
    'before': {'bytes': 2048, 'files': 20},
    'after': {'bytes': sum(len(data) for data in payload.values()), 'files': len(files)},
    'compatibility': {'notesTableSchemaVersion': 3, 'lanceDbVersion': '0.27.2'},
    'validation': {'rows': len(hashes), 'vectorQuery': True, 'fullTextQuery': True},
}
policy = int(os.environ.get('SNAPSHOT_FIXTURE_POLICY', '4'))
(target / 'snapshot.json').write_text(json.dumps({'policyVersion': policy, 'rulesFingerprint': rules_fingerprint, 'files': files, 'result': result}))
print(json.dumps(result))
