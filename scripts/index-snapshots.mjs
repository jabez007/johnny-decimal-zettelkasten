#!/usr/bin/env node
// Git owns the published tree; the MCP owns database maintenance and validation.
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const CONFIG = '.obsidian-indexes.json';
const STORAGE = '.obsidian-vault-mcp';
const COMPANIONS = ['file-hashes.json', 'schema-version.json', 'index-metadata.json'];
const PAYLOAD = ['lancedb', ...COMPANIONS];
const PACKAGE = '@jabez007/obsidian-vault-mcp@2.1.0';
let root;

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root, encoding: null, maxBuffer: 128 * 1024 * 1024,
    ...options,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${command} failed: ${result.error?.message || result.stderr?.toString().trim() || result.stdout?.toString().trim() || result.signal}`);
  }
  return result.stdout;
}
function git(args, options) { return run('git', args, options); }
function setting(name, fallback = '') {
  const result = spawnSync('git', ['config', '--get', name], { cwd: root, encoding: 'utf8' });
  if (result.status === 1) return fallback;
  if (result.status !== 0) throw new Error(result.stderr || 'Cannot read Git configuration');
  return result.stdout.trim();
}
function exists(file) { try { fs.lstatSync(file); return true; } catch (e) { if (e.code === 'ENOENT') return false; throw e; } }
function readJson(file) { return JSON.parse(fs.readFileSync(file, 'utf8')); }
function json(value) { return `${JSON.stringify(value, null, 2)}\n`; }
function same(a, b) {
  return JSON.stringify(Object.entries(a).sort()) === JSON.stringify(Object.entries(b).sort());
}
function digest(bytes, algorithm = 'sha256') { return createHash(algorithm).update(bytes).digest('hex'); }
function requireLf(bytes, name) {
  if (bytes.includes('\r\n')) throw new Error(`CRLF line endings in ${name}. Run node scripts/index-snapshots.mjs normalize-text, review the changes, and restage with git add --renormalize. See docs/index-snapshots.md.`);
  return bytes;
}
function readLf(file) { return requireLf(fs.readFileSync(file), path.relative(root, file)); }
function fileDigest(file) {
  const hash = createHash('sha256');
  const fd = fs.openSync(file, 'r');
  const buffer = Buffer.alloc(1024 * 1024);
  try { let size; while ((size = fs.readSync(fd, buffer)) > 0) hash.update(buffer.subarray(0, size)); }
  finally { fs.closeSync(fd); }
  return hash.digest('hex');
}
function safe(relative) {
  if (typeof relative !== 'string' || !relative || relative.includes('\\') || path.isAbsolute(relative) ||
      relative.split('/').some(part => !part || part === '.' || part === '..')) throw new Error(`Invalid relative path: ${relative}`);
  const absolute = path.join(root, relative);
  let current = root;
  for (const part of relative.split('/')) {
    current = path.join(current, part);
    if (exists(current) && fs.lstatSync(current).isSymbolicLink()) throw new Error(`Symbolic links are unsupported here: ${current}`);
  }
  return absolute;
}
function readConfig() {
  if (!exists(safe(CONFIG))) return { version: 1, vaults: [] };
  return parseConfig(fs.readFileSync(safe(CONFIG)));
}
function parseConfig(bytes) {
  const config = JSON.parse(bytes);
  if (config.version !== 1 || !Array.isArray(config.vaults)) throw new Error(`Invalid ${CONFIG}`);
  const ids = new Set(), paths = new Set();
  for (const vault of config.vaults) {
    if (!/^vaults\/[^/\\]+$/.test(vault.path) || !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(vault.id) || vault.id.includes('..')) {
      throw new Error(`Invalid vault registration in ${CONFIG}`);
    }
    safe(vault.path);
    if (ids.has(vault.id) || paths.has(vault.path)) throw new Error(`Duplicate vault path or ID in ${CONFIG}`);
    ids.add(vault.id); paths.add(vault.path);
  }
  return config;
}
function commitConfig(entries = indexEntries()) {
  const registrations = entries.filter(entry => entry.name === CONFIG);
  if (registrations.some(entry => entry.stage !== '0' || !['100644', '100755'].includes(entry.mode))) {
    throw new Error(`Resolve the staged ${CONFIG} before publishing snapshots`);
  }
  const staged = registrations.length ? blobs(registrations)[0] : null;
  const working = exists(safe(CONFIG)) ? fs.readFileSync(safe(CONFIG)) : null;
  if (staged) requireLf(staged, `staged ${CONFIG}`);
  if (working) requireLf(working, CONFIG);
  if (staged === null ? working !== null : working === null || !staged.equals(working)) {
    throw new Error(`Stage the current ${CONFIG} before publishing snapshots, including intended registration removals`);
  }
  return staged === null ? { version: 1, vaults: [] } : parseConfig(staged);
}
function shared(vault) { return `${STORAGE}/shared/${vault.id}`; }
function live(vault) { return `${STORAGE}/vaults/${vault.id}`; }
function eligible(relative) { return relative.endsWith('.md') && relative.split('/').every(part => !part.startsWith('.')); }
function workingNotes(vault, { allowCrlf = false } = {}) {
  const hashes = {};
  let latestMtimeMs = 0;
  function visit(directory, prefix = '') {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.name.startsWith('.')) continue;
      const relative = prefix + entry.name;
      const absolute = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`Vault symlinks are unsupported for snapshot sharing: ${absolute}`);
      if (entry.isDirectory()) visit(absolute, `${relative}/`);
      else if (entry.isFile() && eligible(relative)) {
        const bytes = fs.readFileSync(absolute);
        if (!allowCrlf) requireLf(bytes, `${vault.path}/${relative}`);
        hashes[relative] = digest(bytes.toString('utf8'), 'md5');
        latestMtimeMs = Math.max(latestMtimeMs, fs.statSync(absolute).mtimeMs);
      }
    }
  }
  visit(safe(vault.path));
  return { hashes, latestMtimeMs };
}
function indexEntries(options) {
  return git(['ls-files', '--stage', '-z'], options).toString().split('\0').filter(Boolean).map(line => {
    const tab = line.indexOf('\t');
    const [mode, oid, stage] = line.slice(0, tab).split(' ');
    return { mode, oid, stage, name: line.slice(tab + 1) };
  });
}
function blobs(entries, options = {}) {
  if (!entries.length) return [];
  const output = git(['cat-file', '--batch'], { ...options, input: entries.map(entry => entry.oid).join('\n') + '\n' });
  let offset = 0;
  return entries.map(() => {
    const end = output.indexOf(10, offset);
    const [, type, rawSize] = output.subarray(offset, end).toString().split(' ');
    const size = Number(rawSize);
    if (end < 0 || type !== 'blob' || !Number.isSafeInteger(size)) throw new Error('Cannot read staged file bytes');
    const content = output.subarray(end + 1, end + 1 + size);
    offset = end + size + 2;
    return content;
  });
}
function stagedNotes(vault, entries) {
  const notes = entries.filter(entry => entry.name.startsWith(`${vault.path}/`) && eligible(entry.name.slice(vault.path.length + 1)));
  for (const entry of notes) {
    if (entry.stage !== '0' || !['100644', '100755'].includes(entry.mode)) throw new Error(`Unmerged or unsupported note: ${entry.name}`);
  }
  const hashes = {};
  const contents = blobs(notes);
  notes.forEach((entry, i) => { hashes[entry.name.slice(vault.path.length + 1)] = digest(requireLf(contents[i], `staged ${entry.name}`).toString('utf8'), 'md5'); });
  return hashes;
}
function validatePayload(directory, files) {
  if (!Array.isArray(files)) throw new Error('Snapshot file inventory is missing');
  const expected = new Set();
  for (const file of files) {
    if (!file || typeof file.path !== 'string' || (!COMPANIONS.includes(file.path) && !file.path.startsWith('lancedb/notes.lance/')) ||
        !/^[a-f0-9]{64}$/.test(file.sha256) || !Number.isSafeInteger(file.bytes) || file.bytes < 0 || expected.has(file.path)) {
      throw new Error('Invalid snapshot file inventory');
    }
    const absolute = safe(`${path.relative(root, directory).split(path.sep).join('/')}/${file.path}`);
    const stat = fs.lstatSync(absolute);
    if (COMPANIONS.includes(file.path)) readLf(absolute);
    if (!stat.isFile() || stat.size !== file.bytes || fileDigest(absolute) !== file.sha256) {
      throw new Error(`Snapshot file is incomplete or modified: ${absolute}. Run git lfs pull if this is an LFS pointer.`);
    }
    expected.add(file.path);
  }
  if (COMPANIONS.some(name => !expected.has(name))) throw new Error('Snapshot companion metadata is missing');
  function visit(dir, prefix = '') {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const relative = prefix + entry.name;
      if (entry.isSymbolicLink()) throw new Error(`Snapshot symlink: ${relative}`);
      if (entry.isDirectory()) visit(path.join(dir, entry.name), `${relative}/`);
      else if (!expected.has(relative) && relative !== 'snapshot.json') throw new Error(`Unexpected snapshot file: ${relative}`);
    }
  }
  visit(directory);
}
function compatibility(value) {
  if (value?.notesTableSchemaVersion !== 3 || value?.lanceDbVersion !== '0.27.2') throw new Error('Unsupported snapshot schema or LanceDB version');
}
function acquire(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  let fd;
  try { fd = fs.openSync(file, 'wx'); }
  catch (e) { if (e.code === 'EEXIST') throw new Error(`Operation is locked: ${file}. Resolve an abandoned lock only after its owner has stopped.`); throw e; }
  fs.writeFileSync(fd, json({ pid: process.pid, hostname: os.hostname(), createdAt: Date.now(), token: randomUUID() }));
  fs.closeSync(fd);
  return () => { if (exists(file)) fs.unlinkSync(file); };
}
function invokeMcp(vault, operation) {
  const command = process.env.OBSIDIAN_SNAPSHOT_MCP;
  const args = [operation, '--vault_path', safe(vault.path), '--workspace_path', root, '--vault_id', vault.id];
  const output = run(command || 'npx', command ? args : ['--yes', PACKAGE, ...args], {
    env: { ...process.env, OBSIDIAN_VAULT_PATH: safe(vault.path), OBSIDIAN_WORKSPACE_PATH: root, OBSIDIAN_VAULT_ID: vault.id },
    timeout: operation === 'obsidian_rag_index' ? 30 * 60 * 1000 : 10 * 60 * 1000,
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const result = JSON.parse(output.toString());
  if (result.success !== true) throw new Error(`${operation}: ${result.message || 'MCP reported failure'}`);
  return result;
}
function childMcp(vault) {
  const result = invokeMcp(vault, 'obsidian_prepare_index_snapshot');
  if (result.success !== true || !/^[a-f0-9]{64}$/.test(result.sourceFingerprint)) throw new Error('MCP did not return a successful snapshot');
  const expected = safe(`${live(vault)}/snapshots/${result.sourceFingerprint}`);
  if (path.resolve(result.snapshotPath) !== expected) throw new Error('MCP returned a snapshot outside the registered vault cache');
  const manifest = readJson(path.join(expected, 'snapshot.json'));
  if (manifest.policyVersion !== 1 || manifest.result?.sourceFingerprint !== result.sourceFingerprint ||
      manifest.result?.success !== true || !result.validation?.vectorQuery || !result.validation?.fullTextQuery) throw new Error('Invalid MCP snapshot manifest');
  compatibility(result.compatibility);
  validatePayload(expected, manifest.files);
  const max = setting('obsidian.snapshotMaxBytes');
  if (max && (!/^\d+$/.test(max) || manifest.files.reduce((total, file) => total + file.bytes, 0) > Number(max))) {
    throw new Error('Snapshot exceeds obsidian.snapshotMaxBytes, or the configured limit is invalid');
  }
  return { directory: expected, files: manifest.files, result };
}
function checkAttributes(names) {
  for (const cached of [false, true]) {
    const args = ['check-attr', ...(cached ? ['--cached'] : []), '-z', '--stdin', 'filter'];
    const values = git(args, { input: names.join('\0') + '\0' }).toString().split('\0');
    for (let i = 0; i < values.length - 1; i += 3) {
      const expected = values[i].includes('/lancedb/') ? 'lfs' : 'unspecified';
      if (values[i + 2] !== expected && !(expected === 'unspecified' && values[i + 2] === 'unset')) {
        throw new Error(`Incorrect ${cached ? 'staged' : 'working'} Git filter for ${values[i]}. Run setup and stage .gitattributes.`);
      }
    }
  }
}
function checkLfAttributes(names, cached = true) {
  if (!names.length) return;
  for (const staged of cached ? [false, true] : [false]) {
    const values = git(['check-attr', ...(staged ? ['--cached'] : []), '-z', '--stdin',
      'text', 'eol', 'filter', 'working-tree-encoding'], { input: names.join('\0') + '\0' }).toString().split('\0');
    for (let i = 0; i < values.length - 1; i += 3) {
      const [name, attribute, value] = values.slice(i, i + 3);
      const expected = attribute === 'text' ? ['set'] : attribute === 'eol' ? ['lf'] : ['unspecified', 'unset'];
      if (!expected.includes(value)) throw new Error(`Unsupported ${staged ? 'staged' : 'working'} LF attributes for ${name}: ${attribute}=${value}. Run setup, review overriding .gitattributes rules, and stage .gitattributes. See docs/index-snapshots.md.`);
    }
  }
}
function checkChangedAttributes(vaults, entries, changed) {
  const scopes = changed.filter(name => path.posix.basename(name) === '.gitattributes')
    .map(name => name === '.gitattributes' ? '' : name.slice(0, -'.gitattributes'.length));
  if (!scopes.length) return;
  const affected = name => scopes.some(scope => name.startsWith(scope));
  // Use staged paths, without reading or hashing working notes. Attribute-only
  // commits must remain possible on machines that cannot run the indexer.
  const text = new Set(entries.map(entry => entry.name).filter(name => /\.(sh|mjs|py|gitattributes)$/.test(name)));
  if (entries.some(entry => entry.name === CONFIG)) text.add(CONFIG);
  const database = [];
  for (const vault of vaults) {
    for (const entry of entries) {
      if (entry.name.startsWith(`${vault.path}/`) && eligible(entry.name.slice(vault.path.length + 1))) text.add(entry.name);
      if (entry.name.startsWith(`${shared(vault)}/lancedb/`)) database.push(entry.name);
      if (entry.name.startsWith(`${shared(vault)}/`) && path.posix.basename(entry.name) === '.gitattributes') {
        throw new Error(`Keep .gitattributes outside the immutable snapshot at ${shared(vault)}; put shared rules in ${STORAGE}/shared/.gitattributes instead`);
      }
    }
    for (const name of [...COMPANIONS, 'snapshot.json']) text.add(`${shared(vault)}/${name}`);
  }
  checkLfAttributes([...text].filter(affected));
  const affectedDatabase = database.filter(affected);
  if (affectedDatabase.length) checkAttributes(affectedDatabase);
}
function publish(vaults, migrate = false, fromHook = false) {
  const defaultEnv = { ...process.env }; delete defaultEnv.GIT_INDEX_FILE;
  const normalIndex = path.resolve(root, git(['rev-parse', '--git-path', 'index'], { env: defaultEnv }).toString().trim());
  const activeIndex = path.resolve(root, process.env.GIT_INDEX_FILE || normalIndex);
  // commit -a supplies Git's locked index. Git rereads it after pre-commit and
  // owns its final commit or rollback. Path-limited commits use a different index.
  const commitIndex = fromHook && activeIndex === `${normalIndex}.lock`
    && exists(activeIndex) && fs.lstatSync(activeIndex).isFile();
  if (activeIndex !== normalIndex && !commitIndex) throw new Error('Snapshot publication requires a normal commit or commit -a, not a path-limited commit or alternate Git index');
  const unlock = acquire(path.resolve(root, git(['rev-parse', '--git-path', 'obsidian-snapshot-publish.lock']).toString().trim()));
  let releaseIndex;
  let transaction;
  let cleanupTransaction = true;
  let installed = [];
  try {
    // For commit -a our lock is index.lock.lock; leave Git's index.lock to Git.
    releaseIndex = acquire(`${activeIndex}.lock`);
    const entries = indexEntries();
    const stagedConfig = commitConfig(entries);
    if (vaults.some(vault => !stagedConfig.vaults.some(item => item.id === vault.id && item.path === vault.path))) {
      throw new Error(`Stage the current ${CONFIG} before publishing snapshots`);
    }
    const autoIndex = setting('obsidian.snapshotAutoIndex', 'true');
    if (!['true', 'false'].includes(autoIndex)) throw new Error('Use obsidian.snapshotAutoIndex=true or false');
    // Check every vault before any indexing starts.
    const checked = vaults.map(vault => {
      const hashes = stagedNotes(vault, entries);
      if (!same(hashes, workingNotes(vault).hashes)) throw new Error(`Stage all Markdown changes in ${vault.path}, including new and deleted notes, before publishing`);
      checkLfAttributes([CONFIG, ...Object.keys(hashes).map(name => `${vault.path}/${name}`),
        ...[...COMPANIONS, 'snapshot.json'].map(name => `${shared(vault)}/${name}`)]);
      const trackedLive = entries.filter(entry => entry.name.startsWith(`${live(vault)}/`) || entry.name.startsWith(`.gemini-obsidian/vaults/${vault.id}/`));
      if (trackedLive.length && !migrate) throw new Error(`Live database is still tracked for ${vault.path}. Run: node scripts/index-snapshots.mjs migrate --vault ${vault.path}`);
      git(['diff', '--quiet', '--', shared(vault)]);
      if (git(['ls-files', '--others', '--exclude-standard', '-z', '--', shared(vault)]).length) throw new Error(`Untracked files exist in ${shared(vault)}; move them aside before publishing`);
      return { vault, hashes, trackedLive };
    });
    const selected = [];
    for (const { vault, hashes, trackedLive } of checked) {
      if (autoIndex === 'true') {
        console.error(`Updating the index for ${vault.path} incrementally...`);
        invokeMcp(vault, 'obsidian_rag_index');
      }
      if (!same(hashes, workingNotes(vault).hashes)) throw new Error(`Notes changed during indexing in ${vault.path}; stage them and retry`);
      const snapshot = childMcp(vault);
      if (!same(hashes, readJson(path.join(snapshot.directory, 'file-hashes.json')))) throw new Error(`Snapshot notes do not match the staged commit for ${vault.path}`);
      const manifest = {
        version: 1, vaultPath: vault.path, vaultId: vault.id, sourceFingerprint: snapshot.result.sourceFingerprint,
        compatibility: snapshot.result.compatibility, validation: snapshot.result.validation, files: snapshot.files,
      };
      checkAttributes([...snapshot.files.map(file => `${shared(vault)}/${file.path}`), `${shared(vault)}/snapshot.json`]);
      selected.push({ vault, snapshot, manifest, trackedLive });
    }
    const parent = safe(`${STORAGE}/.transactions`);
    fs.mkdirSync(parent, { recursive: true });
    transaction = fs.mkdtempSync(path.join(parent, 'publish-'));
    const alternate = path.join(transaction, 'index');
    fs.copyFileSync(activeIndex, alternate);
    const env = { ...process.env, GIT_INDEX_FILE: alternate };
    for (const { vault, snapshot, manifest, trackedLive } of selected) {
      const target = safe(shared(vault));
      const text = json(manifest);
      if (!exists(path.join(target, 'snapshot.json')) || fs.readFileSync(path.join(target, 'snapshot.json'), 'utf8') !== text) {
        const next = path.join(transaction, `new-${vault.id}`), backup = path.join(transaction, `old-${vault.id}`);
        fs.mkdirSync(next);
        for (const entry of PAYLOAD) fs.cpSync(path.join(snapshot.directory, entry), path.join(next, entry), { recursive: true });
        fs.writeFileSync(path.join(next, 'snapshot.json'), text);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        const hadTarget = exists(target);
        if (hadTarget) fs.renameSync(target, backup);
        installed.push({ target, backup, hadTarget });
        fs.renameSync(next, target);
      }
      validatePayload(target, snapshot.files);
      git(['add', '-A', '--', shared(vault)], { env });
      const expected = new Map(snapshot.files.map(file => [`${shared(vault)}/${file.path}`, file]));
      expected.set(`${shared(vault)}/snapshot.json`, { path: 'snapshot.json', bytes: Buffer.byteLength(text), sha256: digest(text) });
      const staged = indexEntries({ env }).filter(entry => expected.has(entry.name));
      if (staged.length !== expected.size) throw new Error('Snapshot files were excluded from Git staging');
      const contents = blobs(staged, { env });
      staged.forEach((entry, i) => {
        const file = expected.get(entry.name), content = contents[i];
        if (file.path.startsWith('lancedb/')) {
          if (content.toString() !== `version https://git-lfs.github.com/spec/v1\noid sha256:${file.sha256}\nsize ${file.bytes}\n`) {
            throw new Error(`Staged database file is not the expected LFS pointer: ${entry.name}`);
          }
        } else if (content.length !== file.bytes || digest(content) !== file.sha256) {
          throw new Error(`Git attributes changed snapshot metadata bytes: ${entry.name}`);
        }
      });
      if (migrate && trackedLive.length) git(['update-index', '--force-remove', '-z', '--stdin'], { env, input: trackedLive.map(entry => entry.name).join('\0') + '\0' });
      console.error(`Prepared ${vault.path}: ${snapshot.result.before.bytes} -> ${snapshot.result.after.bytes} bytes${snapshot.result.reused ? ' (reused export)' : ''}.`);
    }
    // Only snapshot paths and requested live-index removals changed in this copy.
    fs.copyFileSync(alternate, `${activeIndex}.lock`);
    fs.renameSync(`${activeIndex}.lock`, activeIndex);
    installed = [];
  } catch (error) {
    cleanupTransaction = false;
    for (const { target, backup, hadTarget } of installed.reverse()) {
      fs.rmSync(target, { recursive: true, force: true });
      if (hadTarget) fs.renameSync(backup, target);
    }
    cleanupTransaction = true;
    throw error;
  } finally {
    // Preserve backups if filesystem errors prevented rollback.
    if (transaction && cleanupTransaction) fs.rmSync(transaction, { recursive: true, force: true });
    releaseIndex?.(); unlock();
  }
}
function install(vault) {
  const source = safe(shared(vault));
  const manifestBytes = readLf(path.join(source, 'snapshot.json'));
  const manifest = JSON.parse(manifestBytes);
  if (manifest.version !== 1 || manifest.vaultId !== vault.id || manifest.vaultPath !== vault.path) throw new Error('Snapshot registration does not match this vault');
  compatibility(manifest.compatibility);
  validatePayload(source, manifest.files);
  const notes = workingNotes(vault);
  checkLfAttributes([CONFIG, ...Object.keys(notes.hashes).map(name => `${vault.path}/${name}`),
    ...[...COMPANIONS, 'snapshot.json'].map(name => `${shared(vault)}/${name}`)], false);
  if (!same(notes.hashes, readJson(path.join(source, 'file-hashes.json')))) throw new Error('Vault notes differ from the shared snapshot; pull matching notes or publish an updated snapshot first');
  const target = safe(live(vault));
  fs.mkdirSync(target, { recursive: true });
  const unlock = acquire(path.join(target, 'index.lock'));
  let transaction;
  let cleanupTransaction = true;
  const moved = [];
  try {
    const marker = path.join(target, 'installed-snapshot.json');
    const snapshotSha256 = digest(manifestBytes);
    if (exists(marker) && readJson(marker).snapshotSha256 === snapshotSha256 &&
        PAYLOAD.every(entry => exists(path.join(target, entry))) &&
        same(notes.hashes, readJson(path.join(target, 'file-hashes.json')))) {
      const metadataFile = path.join(target, 'index-metadata.json');
      const metadata = readJson(metadataFile);
      if (metadata.latestMtimeMs !== notes.latestMtimeMs || metadata.fileCount !== Object.keys(notes.hashes).length) {
        fs.writeFileSync(`${metadataFile}.tmp`, json({ ...metadata, indexedAt: Date.now(), latestMtimeMs: notes.latestMtimeMs, fileCount: Object.keys(notes.hashes).length }));
        fs.renameSync(`${metadataFile}.tmp`, metadataFile);
      }
      return;
    }
    transaction = fs.mkdtempSync(path.join(target, '.install-'));
    for (const entry of PAYLOAD) fs.cpSync(path.join(source, entry), path.join(transaction, `new-${entry}`), { recursive: true });
    fs.writeFileSync(path.join(transaction, 'new-installed-snapshot.json'), json({ snapshotSha256 }));
    const metadataFile = path.join(transaction, 'new-index-metadata.json');
    fs.writeFileSync(metadataFile, json({ ...readJson(metadataFile), indexedAt: Date.now(), latestMtimeMs: notes.latestMtimeMs, fileCount: Object.keys(notes.hashes).length }));
    validatePayload(source, manifest.files);
    if (fileDigest(path.join(source, 'snapshot.json')) !== snapshotSha256) throw new Error('Shared snapshot changed during installation');
    if (!same(notes.hashes, workingNotes(vault).hashes)) throw new Error('Vault notes changed during installation');
    for (const entry of [...PAYLOAD, 'installed-snapshot.json']) {
      const destination = path.join(target, entry), backup = path.join(transaction, `old-${entry}`);
      const hadTarget = exists(destination);
      if (hadTarget) fs.renameSync(destination, backup);
      moved.push({ destination, backup, hadTarget });
      fs.renameSync(path.join(transaction, `new-${entry}`), destination);
    }
    console.error(`Installed shared index for ${vault.path}. No document embeddings were generated.`);
  } catch (error) {
    cleanupTransaction = false;
    for (const { destination, backup, hadTarget } of moved.reverse()) {
      fs.rmSync(destination, { recursive: true, force: true });
      if (hadTarget) fs.renameSync(backup, destination);
    }
    cleanupTransaction = true;
    throw error;
  } finally {
    // Preserve backups if filesystem errors prevented rollback.
    if (transaction && cleanupTransaction) fs.rmSync(transaction, { recursive: true, force: true });
    unlock();
  }
}
function receive(vaults) {
  const policy = setting('obsidian.snapshotInstall', 'auto');
  if (policy === 'off') return;
  if (policy !== 'auto') throw new Error('Use obsidian.snapshotInstall=auto or off');
  const unlock = acquire(path.resolve(root, git(['rev-parse', '--git-path', 'obsidian-snapshot-receive.lock']).toString().trim()));
  try {
    for (const vault of vaults) {
      const source = safe(shared(vault));
      if (!exists(path.join(source, 'snapshot.json'))) continue;
      // Git has already checked out HEAD. Do not activate edited or conflicted exports.
      git(['diff', '--exit-code', '--quiet', 'HEAD', '--', CONFIG, shared(vault)]);
      for (const relative of [CONFIG, `${shared(vault)}/snapshot.json`]) {
        if (!git(['show', `HEAD:${relative}`]).equals(readLf(safe(relative)))) {
          throw new Error(`Automatic installation requires the committed version of ${relative}`);
        }
      }
      const manifest = readJson(path.join(source, 'snapshot.json'));
      let pointers = false;
      for (const file of manifest.files ?? []) {
        if (!file.path?.startsWith('lancedb/')) continue;
        const absolute = safe(`${shared(vault)}/${file.path}`);
        if (exists(absolute) && fs.statSync(absolute).size < 1024 &&
            fs.readFileSync(absolute, 'utf8').startsWith('version https://git-lfs.github.com/spec/v1\n')) pointers = true;
      }
      if (pointers) {
        console.error(`Downloading shared index files for ${vault.path}...`);
        git(['lfs', 'pull', '--include', `${shared(vault)}/**`, '--exclude', '']);
      }
      install(vault);
    }
  } finally { unlock(); }
}
function normalizeText(vaults) {
  const files = new Set(exists(safe(CONFIG)) ? [CONFIG] : []);
  for (const vault of vaults) {
    for (const name of Object.keys(workingNotes(vault, { allowCrlf: true }).hashes)) files.add(`${vault.path}/${name}`);
    for (const name of [...COMPANIONS, 'snapshot.json']) {
      const relative = `${shared(vault)}/${name}`;
      if (exists(safe(relative))) files.add(relative);
    }
    for (const name of COMPANIONS) {
      const relative = `${live(vault)}/${name}`;
      if (exists(safe(relative))) files.add(relative);
    }
  }
  const changes = [];
  // Preflight every path and inventory before making any edits. Preserve bytes
  // other than CRLF, including files that contain invalid UTF-8 sequences.
  for (const relative of files) {
    const file = safe(relative);
    if (!fs.lstatSync(file).isFile()) throw new Error(`Expected a regular file: ${relative}`);
    const before = fs.readFileSync(file);
    const after = Buffer.from(before.toString('latin1').replaceAll('\r\n', '\n'), 'latin1');
    if (!before.equals(after)) changes.push({ relative, file, before, after });
  }
  for (const vault of vaults) {
    const manifestPath = `${shared(vault)}/snapshot.json`;
    if (!exists(safe(manifestPath))) continue;
    const manifest = readJson(safe(manifestPath));
    for (const change of changes.filter(item => item.relative.startsWith(`${shared(vault)}/`) && item.relative !== manifestPath)) {
      const name = path.posix.basename(change.relative);
      const expected = manifest.files?.find(item => item.path === name);
      if (!expected || expected.bytes !== change.after.length || expected.sha256 !== digest(change.after)) {
        throw new Error(`Cannot normalize ${change.relative} without invalidating its snapshot inventory. Republish from an LF vault. No files were changed.`);
      }
    }
  }
  const locks = [];
  try {
    for (const vault of vaults) {
      if (exists(safe(live(vault))) && changes.some(change => change.relative.startsWith(`${vault.path}/`) || change.relative.startsWith(`${live(vault)}/`))) {
        locks.push(acquire(path.join(safe(live(vault)), 'index.lock')));
      }
    }
    for (const change of changes) {
      if (!fs.readFileSync(change.file).equals(change.before)) throw new Error(`File changed during normalization: ${change.relative}`);
      fs.writeFileSync(change.file, change.after);
      console.error(`Converted CRLF to LF: ${change.relative}`);
    }
  } finally { for (const unlock of locks.reverse()) unlock(); }
  console.error(`Normalized ${changes.length} files. Git staging is unchanged; review and restage the intended changes before publishing.`);
}
function main() {
  root = fs.realpathSync(run('git', ['rev-parse', '--show-toplevel']).toString().trim());
  const [command, ...args] = process.argv.slice(2);
  if (command === 'receive') {
    const [event, ...eventArgs] = args;
    if (!['setup', 'post-merge', 'post-checkout', 'post-rewrite'].includes(event)) throw new Error('Invalid receive hook');
    if (event === 'post-merge' && eventArgs[0] === '1') return;
    if (event === 'post-checkout' && eventArgs[2] !== '1') return;
    if (event === 'post-rewrite' && eventArgs[0] !== 'rebase') return;
    const pending = ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
      ...(event === 'post-rewrite' ? [] : ['rebase-merge', 'rebase-apply'])];
    if (pending.some(name => exists(path.resolve(root, git(['rev-parse', '--git-path', name]).toString().trim())))) return;
    try { receive(readConfig().vaults); }
    catch (error) {
      throw new Error(`Git checkout/setup completed, but shared index installation failed: ${error.message}. Keep the MCP stopped; resolve the error and run bash scripts/install-index-snapshot.sh`);
    }
    return;
  }
  const seen = new Set();
  for (let i = 0; i < args.length; i += 2) {
    if (!['--vault', '--id'].includes(args[i]) || !args[i + 1] || args[i + 1].startsWith('--') || seen.has(args[i]) ||
        (args[i] === '--id' && command !== 'register')) throw new Error('Invalid or missing command option');
    seen.add(args[i]);
  }
  const option = name => { const i = args.indexOf(name); return i < 0 ? undefined : args[i + 1]; };
  // Publication selection must use the configuration in Git's active index.
  // The consistency check runs even when no vault appears to be affected.
  if (command === 'hook') {
    const policy = setting('obsidian.snapshotPolicy', 'required');
    if (policy === 'off') return;
    if (policy !== 'required') throw new Error('Use obsidian.snapshotPolicy=required or off');
    const entries = indexEntries();
    const config = commitConfig(entries);
    const changed = git(['diff', '--cached', '--name-only', '--no-renames', '-z']).toString().split('\0').filter(Boolean);
    checkChangedAttributes(config.vaults, entries, changed);
    const contentChanges = changed.filter(name => path.posix.basename(name) !== '.gitattributes');
    const affected = config.vaults.filter(vault => contentChanges.some(file => file === CONFIG ||
      (file.startsWith(`${vault.path}/`) && eligible(file.slice(vault.path.length + 1))) || file.startsWith(`${shared(vault)}/`) || file.startsWith(`${live(vault)}/`)));
    if (affected.length) publish(affected, false, true);
    else if (changed.some(file => /^(\.obsidian-vault-mcp|\.gemini-obsidian)\/vaults\//.test(file))) throw new Error('Register and migrate the tracked live index before committing it');
    return;
  }
  const config = readConfig();
  if (command === 'normalize-text') {
    const selected = config.vaults.filter(vault => !option('--vault') || vault.path === option('--vault') || vault.id === option('--vault'));
    if (option('--vault') && !selected.length) throw new Error('No matching registered vault');
    normalizeText(selected);
    return;
  }
  if (command === 'register') {
    const supplied = option('--vault');
    if (!supplied) throw new Error('register requires --vault and --id');
    const relative = path.relative(root, path.resolve(root, supplied)).split(path.sep).join('/');
    let vault = config.vaults.find(item => item.path === relative);
    if (!vault) {
      vault = { path: relative, id: option('--id') };
      if (!/^vaults\/[^/\\]+$/.test(relative) || !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(vault.id ?? '') || vault.id.includes('..')) throw new Error('Invalid vault path or ID');
      safe(relative);
      if (config.vaults.some(item => item.id === vault.id)) throw new Error('Vault ID is already registered');
      config.vaults.push(vault);
      fs.writeFileSync(safe(CONFIG), json(config));
    }
    console.log(vault.id);
    return;
  }
  if (['prepare', 'migrate', 'install'].includes(command)) {
    const selected = config.vaults.filter(vault => !option('--vault') || vault.path === option('--vault') || vault.id === option('--vault'));
    if (!selected.length) throw new Error(`No matching vault in ${CONFIG}; run setup or register --vault vaults/name --id stable-id`);
    if (command === 'install') for (const vault of selected) install(vault);
    else publish(selected, command === 'migrate');
    return;
  }
  throw new Error('Usage: node scripts/index-snapshots.mjs register|prepare|migrate|install|normalize-text [--vault vaults/name] [--id stable-id]');
}
try { main(); } catch (error) { console.error(`Index snapshot: ${error.message}`); process.exitCode = 1; }
