// Synthetic vectors seed a real database without downloading an embedding model.
import * as fs from 'node:fs';
import * as path from 'node:path';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
const [release, root, vaultPath, id] = process.argv.slice(2);
const require = createRequire(path.join(release, 'package.json'));
const lance = require('@lancedb/lancedb');
const { Schema, Field, Utf8, List, Float32, FixedSizeList } = require('apache-arrow');
const schema = new Schema([
  new Field('id', new Utf8(), false), new Field('path', new Utf8(), false),
  new Field('text', new Utf8(), false), new Field('embedding_text', new Utf8(), false),
  new Field('heading_path', new Utf8(), false),
  new Field('vector', new FixedSizeList(384, new Field('item', new Float32(), false)), false),
  new Field('entities', new List(new Field('item', new Utf8(), true)), false),
  new Field('communities', new List(new Field('item', new Utf8(), true)), false),
]);
const hashes = {}, rows = [];
let latest = 0;
for (const name of fs.readdirSync(path.join(root, vaultPath))) {
  if (!name.endsWith('.md')) continue;
  const file = path.join(root, vaultPath, name), text = fs.readFileSync(file, 'utf8');
  hashes[name] = createHash('md5').update(text).digest('hex');
  latest = Math.max(latest, fs.statSync(file).mtimeMs);
  if (text) rows.push({ id: name, path: name, text, embedding_text: text, heading_path: '', vector: Array(384).fill(0.1), entities: [], communities: [] });
}
const store = path.join(root, '.obsidian-vault-mcp/vaults', id);
fs.mkdirSync(store, { recursive: true });
const db = await lance.connect(path.join(store, 'lancedb'));
if ((await db.tableNames()).includes('notes')) await db.dropTable('notes');
const table = await db.createTable('notes', rows, { schema });
await table.createIndex('embedding_text', { config: lance.Index.fts() });
if (rows.length) {
  for (let i = 0; i < 8; i++) { await table.delete('true'); await table.add(rows); }
}
table.close(); db.close();
fs.writeFileSync(path.join(store, 'file-hashes.json'), JSON.stringify(hashes));
fs.writeFileSync(path.join(store, 'schema-version.json'), JSON.stringify({ notesTableSchemaVersion: 3 }));
fs.writeFileSync(path.join(store, 'index-metadata.json'), JSON.stringify({ indexedAt: Date.now(), latestMtimeMs: latest, fileCount: Object.keys(hashes).length }));
