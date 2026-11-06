#!/usr/bin/env node
// Lists and checks the proposal queue described in
// references/librarian/proposal-queue.md. It reads the vault and never writes.
import * as fs from 'node:fs';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';

const USAGE = 'Usage: node scripts/proposal-queue.mjs list|check [--vault vaults/name] [P-YYYYMMDD-XXXX ...]';
const STATES = ['pending', 'deferred', 'approved', 'applied', 'rejected', 'superseded'];
const OPEN = ['pending', 'deferred', 'approved'];
const CLOSED = STATES.filter(state => !OPEN.includes(state));
const SECTIONS = ['Change', 'Why', 'Evidence', 'Conflicts', 'Sensitivity check', 'Links', 'Log entry', 'Open questions', 'Review'];
const SOURCE_ID = /^S-\d{8}-[0-9A-F]{4}$/;
const PROPOSAL_ID = /^P-\d{8}-[0-9A-F]{4}$/;
const DATE = /^\d{4}-\d{2}-\d{2}(T[\d:.]+Z)?$/;

function repoRoot() {
  const result = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  return result.status === 0 ? result.stdout.trim() : process.cwd();
}

// The records use a small YAML subset: scalars, flow lists, and block lists.
// obsidian_update_frontmatter rewrites flow lists as block lists, so both forms
// are accepted.
function scalar(raw) {
  const value = raw.trim();
  if (value === '' || value === '~' || value === 'null') return null;
  if (value.startsWith("'") && value.endsWith("'") && value.length > 1) return value.slice(1, -1).replace(/''/g, "'");
  if (value.startsWith('"') && value.endsWith('"') && value.length > 1) return JSON.parse(value);
  return value;
}
function parseYaml(text, label) {
  const data = {};
  let listKey;
  for (const line of text.split('\n')) {
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    const item = /^\s*- (.*)$/.exec(line);
    if (item && listKey) { (data[listKey] ??= []).push(scalar(item[1])); continue; }
    const pair = /^([A-Za-z_][\w-]*):(?: (.*))?$/.exec(line);
    if (!pair) throw new Error(`${label}: cannot read line "${line}"`);
    const [, key, raw = ''] = pair;
    // A key with no value is null unless block list items follow it.
    listKey = raw.trim() === '' ? key : undefined;
    const flow = /^\[(.*)\]$/.exec(raw.trim());
    data[key] = flow ? flow[1].split(',').map(scalar).filter(value => value !== null) : scalar(raw);
  }
  return data;
}
function splitRecord(text, label) {
  const match = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(text.replace(/\r\n/g, '\n'));
  if (!match) throw new Error(`${label}: missing YAML frontmatter`);
  return { meta: parseYaml(match[1], label), body: match[2] };
}
function sections(body, level) {
  const marker = '#'.repeat(level) + ' ';
  const found = [];
  let current;
  let fence;
  for (const line of body.split('\n')) {
    // Headings inside a ~~~~ block belong to the proposed note, not the record.
    if (!fence && /^(~~~~|````)/.test(line)) fence = line.slice(0, 4);
    else if (fence && line.trimEnd() === fence) fence = undefined;
    else if (!fence && line.startsWith(marker)) { current = { title: line.slice(marker.length).trim(), lines: [] }; found.push(current); continue; }
    if (current) current.lines.push(line);
  }
  return found;
}
function fences(lines) {
  const blocks = [];
  let block;
  for (const line of lines) {
    if (!block && /^~~~~[A-Za-z]*\s*$/.test(line)) { block = []; continue; }
    if (block && /^~~~~\s*$/.test(line)) { blocks.push(block.join('\n')); block = undefined; continue; }
    if (block) block.push(line);
  }
  if (block) throw new Error('unclosed ~~~~ block');
  return blocks;
}
function occurrences(text, part) {
  let count = 0;
  for (let at = text.indexOf(part); at !== -1; at = text.indexOf(part, at + 1)) count++;
  return count;
}
function safeTarget(target) {
  return typeof target === 'string' && target.endsWith('.md') && !target.includes('\\') && !path.isAbsolute(target) &&
    target.split('/').every(part => part && part !== '.' && part !== '..' && !part.startsWith('.'));
}
function date(value) { return typeof value === 'string' && DATE.test(value); }

function readRecords(vault, folder, pattern) {
  const directory = path.join(vault, folder);
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true })
    .filter(entry => entry.isFile() && entry.name.endsWith('.md'))
    .map(entry => {
      const file = path.join(directory, entry.name);
      const id = entry.name.slice(0, -3);
      const record = { id, file, problems: [] };
      if (!pattern.test(id)) record.problems.push(`file name ${entry.name} is not an ID such as ${folder === '.sources' ? 'S' : 'P'}-20261023-8F3D.md`);
      try { Object.assign(record, splitRecord(fs.readFileSync(file, 'utf8'), entry.name)); }
      catch (error) { record.problems.push(error.message); }
      return record;
    });
}

function checkSource(source) {
  const { meta, body, problems } = source;
  if (!meta) return;
  if (meta.record_type !== 'knowledge-source') problems.push('record_type must be knowledge-source');
  if (meta.source_id !== source.id) problems.push(`source_id ${meta.source_id} does not match the file name`);
  if (!meta.source_kind) problems.push('source_kind is missing');
  if (!date(meta.captured_at)) problems.push('captured_at must be a date such as \'2026-10-23\'');
  const excerpts = sections(body, 2).find(section => section.title === 'Excerpts');
  if (!excerpts || !excerpts.lines.some(line => line.startsWith('>'))) problems.push('## Excerpts needs at least one quoted passage');
}

function checkProposal(proposal, vault, sourceIds, proposalIds) {
  const { meta, body, problems } = proposal;
  if (!meta) return;
  if (meta.record_type !== 'knowledge-proposal') problems.push('record_type must be knowledge-proposal');
  if (meta.proposal_id !== proposal.id) problems.push(`proposal_id ${meta.proposal_id} does not match the file name`);
  if (!STATES.includes(meta.state)) problems.push(`state must be one of ${STATES.join(', ')}`);
  if (!/^[1-9]\d*$/.test(meta.revision ?? '')) problems.push('revision must be a positive whole number');
  if (!['create', 'update'].includes(meta.operation)) problems.push('operation must be create or update');
  if (!safeTarget(meta.target_path)) problems.push('target_path must be a vault-relative .md path outside hidden folders');
  if (!date(meta.created_at) || !date(meta.updated_at)) problems.push('created_at and updated_at must be dates such as \'2026-10-23\'');
  if (!Array.isArray(meta.source_ids)) problems.push('source_ids must be a list, such as [] or [S-20261023-8F3D]');
  else for (const id of meta.source_ids) if (!sourceIds.has(id)) problems.push(`source ${id} has no record in .sources/`);
  if (meta.state === 'applied' && !date(meta.applied_at)) problems.push('an applied proposal needs applied_at');
  if (meta.state === 'superseded' && !proposalIds.has(meta.superseded_by)) problems.push('a superseded proposal needs superseded_by naming another proposal');

  const titles = sections(body, 2).map(section => section.title);
  for (const name of SECTIONS) if (!titles.includes(name)) problems.push(`missing section ## ${name}`);
  const change = sections(body, 2).find(section => section.title === 'Change');
  if (!change) return;

  let parts;
  try {
    parts = sections(change.lines.join('\n'), 3).map(part => ({ title: part.title, blocks: fences(part.lines) }));
  } catch (error) { problems.push(`## Change: ${error.message}`); return; }
  const replaces = parts.filter(part => part.title === 'Replace');
  const created = parts.filter(part => part.title === 'New note');
  const frontmatter = parts.filter(part => part.title === 'Frontmatter');
  for (const part of parts) if (!['Replace', 'New note', 'Frontmatter'].includes(part.title)) problems.push(`## Change has an unknown subsection ### ${part.title}`);
  for (const part of replaces) if (part.blocks.length !== 2) problems.push('each ### Replace needs two ~~~~ blocks: the text to replace, then its replacement');
  for (const part of [...created, ...frontmatter]) if (part.blocks.length !== 1) problems.push(`### ${part.title} needs exactly one ~~~~ block`);
  if (frontmatter.length > 1) problems.push('use one ### Frontmatter subsection');
  for (const part of frontmatter) {
    try { parseYaml(part.blocks[0] ?? '', '### Frontmatter'); } catch (error) { problems.push(error.message); }
  }
  if (meta.operation === 'create' && (created.length !== 1 || replaces.length || frontmatter.length)) problems.push('a create needs one ### New note and nothing else under ## Change');
  if (meta.operation === 'update' && (created.length || !replaces.length && !frontmatter.length)) problems.push('an update needs ### Replace or ### Frontmatter subsections and no ### New note');

  // The queue only promises a clean apply for open proposals. A closed one
  // describes a target that has since moved on.
  if (!OPEN.includes(meta.state) || !safeTarget(meta.target_path)) return;
  const target = path.join(vault, meta.target_path);
  const exists = fs.existsSync(target);
  if (meta.operation === 'create' && exists) problems.push(`${meta.target_path} already exists`);
  if (meta.operation !== 'update') return;
  if (!exists) { problems.push(`${meta.target_path} does not exist`); return; }
  // Apply the replacements in order to a copy, the way publishing will, so
  // an earlier edit that removes a later edit's text is caught.
  const original = fs.readFileSync(target, 'utf8');
  let text = original;
  replaces.forEach((part, index) => {
    const [before, after] = part.blocks;
    if (before === undefined) return;
    if (before.trim() === '') { problems.push(`Replace ${index + 1}: the text to replace is empty`); return; }
    const count = occurrences(text, before);
    if (count === 1) { text = text.replace(before, () => after ?? ''); return; }
    // Publishing may have stopped partway. Matching replacement text does
    // not prove which edit put it there, so someone has to confirm it.
    if (count === 0 && meta.state === 'approved' && after && occurrences(text, after) === 1) {
      problems.push(`Replace ${index + 1}: the text to replace is gone and its replacement occurs once. ` +
        'If publishing stopped partway, confirm in the note that this edit landed and skip it');
      return;
    }
    if (count === 0 && occurrences(original, before) === 1) {
      problems.push(`Replace ${index + 1}: an earlier replacement in this proposal removes the text to replace`);
      return;
    }
    problems.push(count === 0
      ? `Replace ${index + 1}: the text to replace is no longer in ${meta.target_path}`
      : `Replace ${index + 1}: the text to replace occurs ${count} times in ${meta.target_path}; it must occur once`);
  });
}

function loadVault(vault, root) {
  const label = path.relative(root, vault) || '.';
  const sources = readRecords(vault, '.sources', SOURCE_ID);
  const proposals = readRecords(vault, '.proposals', PROPOSAL_ID);
  const sourceIds = new Set(sources.map(source => source.id));
  const proposalIds = new Set(proposals.map(proposal => proposal.id));
  sources.forEach(checkSource);
  proposals.forEach(proposal => checkProposal(proposal, vault, sourceIds, proposalIds));
  return { label, sources, proposals };
}

function main() {
  const root = repoRoot();
  const [command, ...args] = process.argv.slice(2);
  if (!['list', 'check'].includes(command)) throw Object.assign(new Error(USAGE), { usage: true });
  let selected;
  const ids = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--vault' && args[i + 1] && !selected) selected = args[++i];
    else if (PROPOSAL_ID.test(args[i])) ids.push(args[i]);
    else throw Object.assign(new Error(USAGE), { usage: true });
  }
  const vaults = selected ? [path.resolve(root, selected)]
    : fs.readdirSync(path.join(root, 'vaults'), { withFileTypes: true })
      .filter(entry => entry.isDirectory() && !entry.name.startsWith('.'))
      .map(entry => path.join(root, 'vaults', entry.name));
  if (selected && !fs.statSync(vaults[0], { throwIfNoEntry: false })?.isDirectory()) throw new Error(`No vault at ${selected}`);

  let problems = 0;
  const found = new Set();
  for (const { label, sources, proposals } of vaults.map(vault => loadVault(vault, root))) {
    const chosen = ids.length ? proposals.filter(proposal => ids.includes(proposal.id)) : proposals;
    chosen.forEach(proposal => found.add(proposal.id));
    if (command === 'list') {
      // A record with a missing or invalid state still needs attention.
      const open = chosen.filter(proposal => !CLOSED.includes(proposal.meta?.state));
      console.log(`${label}: ${open.length} open, ${chosen.length - open.length} closed`);
      for (const proposal of open) {
        const { state = '?', revision = '?', operation = '?', target_path: target = '?' } = proposal.meta ?? {};
        const status = proposal.problems.length ? `${proposal.problems.length} problem(s), run check` : 'ok';
        console.log(`  ${proposal.id}  ${state} r${revision}  ${operation} ${target}  ${status}`);
      }
      continue;
    }
    // A named proposal is checked with the source records it cites.
    const cited = new Set(chosen.flatMap(proposal => Array.isArray(proposal.meta?.source_ids) ? proposal.meta.source_ids : []));
    const records = ids.length ? [...sources.filter(source => cited.has(source.id)), ...chosen] : [...sources, ...chosen];
    for (const record of records) {
      for (const problem of record.problems) console.log(`${path.relative(root, record.file)}: ${problem}`);
      problems += record.problems.length;
    }
  }
  for (const id of ids) if (!found.has(id)) { console.log(`no proposal ${id} in ${selected ?? 'any vault'}`); problems++; }
  if (command === 'check') console.log(problems ? `${problems} problem(s) found.` : 'The proposal queue is consistent.');
  if (problems) process.exitCode = 1;
}
try { main(); } catch (error) { console.error(`Proposal queue: ${error.message}`); process.exitCode = error.usage ? 2 : 1; }
