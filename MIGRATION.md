# Migration guides

This file covers two upgrades. Apply each one your copy of the template has not
taken yet.

- [Retire vault-based agent memory](#retire-vault-based-agent-memory)
- [Migrate to obsidian-vault-mcp v2](#migrating-to-obsidian-vault-mcp-v2)

## Retire vault-based agent memory

Earlier versions of this template made the vault the memory of every coding
agent. A `SessionStart` hook injected a boot context, agents wrote session logs
to `JRNL/AGNT/` and rules to `AGNT/`, and `scripts/compile-sessions.sh` mined
CLI transcripts into more rules. This version removes that machinery. The vault
is now a knowledge library that agents read and add to only with your approval.

If you want agents to remember earlier sessions, configure a memory provider
outside this repository. [Hindsight coexistence](docs/hindsight-coexistence.md)
shows one setup. The [design note](docs/design/knowledge-memory-separation.md)
explains the reasoning.

Pulling this change does not touch your notes. Your `AGNT/` and `JRNL/AGNT/`
notes stay where they are until you run the steps below. Every step previews
by default, and the archive step can be undone.

### What changes when you pull

- These files are deleted: `.claude/settings.json`,
  `.claude/hooks/session-start.sh`, `.codex/hooks/session-start.sh`,
  `scripts/agent-memory-context.sh`, and `scripts/compile-sessions.sh`.
  `.codex/config.toml` no longer enables hooks.
- Agents stop writing session logs, procedural rules, and "Agent Staff Report"
  sections in daily notes.
- Agent instructions treat existing `AGNT/` and `JRNL/AGNT/` notes as read-only
  history. The `daily-reviewer` skips them.
- `sqlite3` is no longer needed.
- The Gemini hook in `~/.gemini/` stays until you remove it in step 2, because
  it lives outside this repository.

If you edited one of the deleted files, Git reports a modify/delete conflict
when you pull. Save your version with `git show HEAD:<path>` before you resolve
it.

### 1. Take an inventory

```bash
./scripts/migrate-agent-memory.sh inventory
```

The command is read-only. It uses the vault in `~/.obsidian-mcp.config.json`.
Pass `--vault vaults/<name>` to choose another, and `--format tsv` for output
you can sort or load into a spreadsheet. The report lists:

- procedural rules in `AGNT/`
- session logs in `JRNL/AGNT/`
- legacy indexes and Bases, such as `_SYS/JDEX_AGNT.base`
- curated notes that link to or embed legacy notes
- lines that look like credentials, for you to review by hand
- legacy files that Git does not track or that have uncommitted changes
- the legacy Gemini hook, if it is still registered

### 2. Remove the Gemini hook

Skip this step if the inventory does not report the hook.

```bash
./scripts/migrate-agent-memory.sh legacy-hooks           # preview
./scripts/migrate-agent-memory.sh legacy-hooks --apply
```

The command copies `~/.gemini/settings.json` to
`~/.gemini/settings.json.agent-memory-backup`. Then it removes only the
`agent-memory-boot` entry. It deletes `~/.gemini/hooks/agent-memory-boot.sh`
and `~/.gemini/hooks/agent-memory-context.sh` only when they carry the marker
this template wrote into them. Other hooks and settings stay as they were.
Running `./.gemini/setup-environment.sh` does the same cleanup. To undo it,
copy the backup over `settings.json`.

### 3. Promote what is worth keeping

Some legacy notes hold knowledge you want in the vault. Ask an agent to review
one with the promotion workflow, for example: "Review AGNT.11.01 for promotion
to a curated note." The agent follows
[`references/librarian/knowledge-promotion.md`](references/librarian/knowledge-promotion.md).
It verifies each claim, proposes a note, and writes nothing until you approve.

Sort each legacy note into one of three groups:

- A decision or fact about your work or projects. Promote it as a curated note.
- An instruction for how agents behave, such as "use pytest in this repo". Move
  it to that project's `AGENTS.md` or `CLAUDE.md`, or to your memory provider.
- Session narrative. Promote a durable insight from it, never the log itself.

Review every file the inventory flags as possibly sensitive before you promote
anything from it.

### 4. Commit untracked logs

The archive step refuses legacy files that Git does not track or that have
uncommitted changes, because moving them would lose their history. Commit them
to the vault repository first:

```bash
git -C vaults/<name> add JRNL/AGNT AGNT
git -C vaults/<name> commit -m "chore: commit remaining agent session logs"
```

### 5. Resolve inbound links

Archiving moves legacy notes out of the vault's visible tree, so links and
embeds that point at them stop resolving. Daily notes that embed session logs,
such as `![[JRNL/AGNT/2026-04-24-1500#Crystallized Rules]]`, are the common
case. For each inbound link the inventory lists, pick one:

- Edit the linking note. Point the link at the promoted note, or replace the
  embed with a sentence.
- Accept the broken link and pass `--allow-inbound-links` to `archive`. The
  target stays in `.archive/agent-memory/` and in Git history.

### 6. Archive

Archive the session logs and the rules together, or one group at a time:

```bash
./scripts/migrate-agent-memory.sh archive --scope logs            # preview
./scripts/migrate-agent-memory.sh archive --scope logs --apply
./scripts/migrate-agent-memory.sh archive --scope rules --apply   # later, after promotion
```

`--scope all` is the default and archives both groups. The command:

1. Refuses with exit code 2 if a precondition from steps 4 or 5 fails, or if
   the destination already exists.
2. Moves `AGNT/`, `JRNL/AGNT/`, and `_SYS/JDEX_AGNT.base` with `git mv` into
   `<vault>/.archive/agent-memory/`, keeping their relative paths.
3. Records each file's SHA-256 in `.archive/agent-memory/MANIFEST.tsv` and
   checks every file against it after the move.
4. Stages the result without committing it.

Review the staged change with `git status`, then commit it. Obsidian and the
MCP indexer skip hidden folders, so archived notes leave search and the file
explorer. If the snapshot hooks are installed, the next commit re-indexes the
vault. Otherwise, run `obsidian_rag_index` once.

### Undo the archive

```bash
./scripts/migrate-agent-memory.sh restore           # preview
./scripts/migrate-agent-memory.sh restore --apply
```

`restore` moves every archived path back with `git mv`, checks each file
against its recorded checksum, and removes the manifest. It works before or
after you commit the archive, and it reverses every scope you archived. Commit
the result. If you already committed the archive and have made no later
changes to those files, `git revert` on the archive commit works too.

### Merge the update into your fork

If your vault repository started from this template, merge the update from the
template remote. Add the remote once if you have not already:

```bash
git remote add template https://github.com/jabez007/johnny-decimal-zettelkasten.git
git fetch template
git merge template/master
./scripts/sync-assets.sh
```

Your notes do not conflict. The only vault this update edits is the sample in
`vaults/example/`. Conflicts appear only in scripts, agent policies, or harness
files you edited. For agent policies, keep your
change in `.agents/agents/` and regenerate. Then work through steps 1 to 6 for
each of your vaults.

## Migrating to obsidian-vault-mcp v2

The Obsidian MCP backend was renamed from `gemini-obsidian` to
**`obsidian-vault-mcp`** and released as v2.0.0. This template now targets that
version, which also unlocked Claude Code and OpenCode support.

**Your vault conventions did not change.** ACID notation, the
`entities`/`communities`/`status` frontmatter, the Johnny-Decimal folder layout,
and every note you have written remain exactly as they were. This migration only
touches host plugin registrations, index storage, and the RAG index itself.

### TL;DR

```bash
git pull
./scripts/migrate-v2.sh

# Then run the setup script for each harness you actually use:
./.claude/setup-environment.sh      # Claude Code
./.codex/setup-environment.sh       # Codex CLI
./.gemini/setup-environment.sh      # Gemini CLI
./.opencode/setup-environment.sh    # OpenCode
```

The one step you cannot skip is the **RAG index rebuild** — see below.

### The one thing that will silently break

v2 migrated the embedding stack from the deprecated `@xenova/transformers` 2.x
to `@huggingface/transformers` 4.x. The model (`Xenova/all-MiniLM-L6-v2`) and
the 384-dimensional vectors are unchanged, but **vectors produced by the new
stack are not numerically identical to the old ones.**

An index containing both old and new chunks returns degraded rankings with **no
error, no warning, and no visible symptom** other than semantic search quietly
getting worse. A one-time full rebuild is the only fix:

```bash
npx -y @jabez007/obsidian-vault-mcp@2 obsidian_rag_index --force_reindex true
```

`./scripts/migrate-v2.sh` offers to run this for you.

### What changed

| Area | v1 | v2 |
| :--- | :--- | :--- |
| Repository | `jabez007/gemini-obsidian` | `jabez007/obsidian-vault-mcp` |
| MCP server key | `gemini-obsidian` | `obsidian-vault-mcp` |
| Distribution | clone + `npm install` + `npm run build` | npm: `npx -y @jabez007/obsidian-vault-mcp@2` |
| Codex plugin | `gemini-obsidian` @ `gemini-obsidian-repo` | `obsidian-vault-mcp` @ `obsidian-vault-mcp-repo` |
| Index storage | `.gemini-obsidian/` | `.obsidian-vault-mcp/` (auto-renamed) |
| Config file | `~/.gemini-obsidian.config.json` | `~/.obsidian-mcp.config.json` (legacy still read) |
| Embedding stack | `@xenova/transformers` 2.x | `@huggingface/transformers` 4.x |

#### Behavior changes worth knowing

- `obsidian_create_note` and `obsidian_move_note` now **refuse to overwrite** an
  existing file unless you pass `overwrite: true`. In a Johnny-Decimal vault a
  refusal almost always means the ACID ID is already taken — resolve the
  collision rather than forcing the write.
- Per-call `vault_path` / `workspace_path` overrides are now **bounded to the
  configured vault**, so a prompt-injected note cannot redirect tools elsewhere.
  To work across several vaults in one session:
  ```bash
  export OBSIDIAN_ALLOWED_VAULTS="/path/to/repo/vaults"
  ```
- Note-writing tools re-index the changed note inside the server, so no separate
  re-index call is needed after a write.

### What `migrate-v2.sh` does

Each step checks current state first, so the script is safe to re-run.

1. Removes the legacy Codex plugin `gemini-obsidian` and its
   `gemini-obsidian-repo` marketplace.
2. Removes the legacy Gemini extension `gemini-obsidian`.
3. Offers to delete the stale `~/.codex/vendor/gemini-obsidian` checkout that v1
   cloned and built (v2 installs from npm, so nothing uses it).
4. Rewrites `.gitattributes` LFS patterns from `.gemini-obsidian/**` to
   `.obsidian-vault-mcp/**`.
5. Reports on the storage directory rename (the server handles it automatically
   on first access, preserving indexes and file hashes).
6. Reports on your vault configuration file.
7. Offers to run the mandatory `--force_reindex` rebuild.
8. Regenerates the per-harness assets via `scripts/sync-assets.sh`.

It never modifies vault note content.

### Repository changes in this template

#### Doctrine is no longer duplicated

Previously the librarian doctrine existed twice — in `references/librarian/` and
again in `.gemini/skills/librarian-vault-manager/references/` — and the two had
already drifted apart. Now there is one canonical copy and a generator.

**Canonical (edit these):**

```text
references/librarian/*.md                        shared doctrine
.agents/skills/librarian-vault-manager/SKILL.md  skill body
.agents/agents/*.md                              agent policies
```

**Generated (never edit — `scripts/sync-assets.sh` overwrites them):**

```text
.claude/skills/…   .claude/agents/*.md
.gemini/skills/…   .gemini/agents/*.md
                   .opencode/agents/*.md
                   .codex/agents/*.toml   .codex/config.toml
```

Run `./scripts/sync-assets.sh` after editing any canonical file. CI reruns it
and fails the build if generated files drift, so this cannot rot again.

Agent policy bodies reference MCP tools through a `{{MCP_PREFIX}}` placeholder,
because each harness namespaces MCP tools differently:

| Harness | Prefix |
| :--- | :--- |
| Claude Code | `mcp__obsidian-vault-mcp__` |
| Gemini CLI | `mcp_obsidian-vault-mcp_` |
| OpenCode | `obsidian-vault-mcp_` |
| Codex CLI | *(bare — the plugin namespaces at call time)* |

#### If you customized your agents

If you edited files under `.gemini/agents/` or `.codex/agents/`, those edits
will be **overwritten** by the generator. Port them to the canonical policy in
`.agents/agents/<name>.md` and re-run `./scripts/sync-assets.sh`. Your changes
then propagate to all four harnesses instead of one.

Check what you would lose before pulling:

```bash
git diff HEAD~1 -- .gemini/agents .codex/agents
```

#### Session compilation and the Recent Activity Map

The v2 release extended `scripts/compile-sessions.sh` to four harnesses and
fixed the boot hook's Recent Activity Map. Both were later removed. See
[Retire vault-based agent memory](#retire-vault-based-agent-memory).

### Troubleshooting

**Semantic search got worse after upgrading.** You have a mixed index. Run the
`--force_reindex` rebuild above.

**`codex plugin add` cannot find the plugin.** The marketplace name changed. Run
`codex plugin marketplace add jabez007/obsidian-vault-mcp`, then
`codex plugin add obsidian-vault-mcp@obsidian-vault-mcp-repo`.

**Tools are not found by an agent.** The server key changed, so the tool prefix
changed with it. If you hand-edited an agent policy, update
`mcp_gemini-obsidian_*` to your harness's prefix from the table above — or
better, move the edit into `.agents/agents/` and regenerate.

**CI fails with "Generated harness assets are out of sync."** You edited a
generated file, or edited a canonical file without regenerating. Run
`./scripts/sync-assets.sh` and commit the result.
