# Migrating to obsidian-vault-mcp v2

The Obsidian MCP backend was renamed from `gemini-obsidian` to
**`obsidian-vault-mcp`** and released as v2.0.0. This template now targets that
version, which also unlocked Claude Code and OpenCode support.

**Your vault conventions did not change.** ACID notation, the
`entities`/`communities`/`status` frontmatter, the Johnny-Decimal folder layout,
and every note you have written remain exactly as they were. This migration only
touches host plugin registrations, index storage, and the RAG index itself.

## TL;DR

```bash
git pull
./scripts/migrate-v2.sh
./.claude/setup-environment.sh     # run for each harness you actually use
```

The one step you cannot skip is the **RAG index rebuild** — see below.

## The one thing that will silently break

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

## What changed

| Area | v1 | v2 |
| :--- | :--- | :--- |
| Repository | `jabez007/gemini-obsidian` | `jabez007/obsidian-vault-mcp` |
| MCP server key | `gemini-obsidian` | `obsidian-vault-mcp` |
| Distribution | clone + `npm install` + `npm run build` | npm: `npx -y @jabez007/obsidian-vault-mcp@2` |
| Codex plugin | `gemini-obsidian` @ `gemini-obsidian-repo` | `obsidian-vault-mcp` @ `obsidian-vault-mcp-repo` |
| Index storage | `.gemini-obsidian/` | `.obsidian-vault-mcp/` (auto-renamed) |
| Config file | `~/.gemini-obsidian.config.json` | `~/.obsidian-mcp.config.json` (legacy still read) |
| Embedding stack | `@xenova/transformers` 2.x | `@huggingface/transformers` 4.x |

### Behavior changes worth knowing

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

## What `migrate-v2.sh` does

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

## Repository changes in this template

### Doctrine is no longer duplicated

Previously the librarian doctrine existed twice — in `references/librarian/` and
again in `.gemini/skills/librarian-vault-manager/references/` — and the two had
already drifted apart. Now there is one canonical copy and a generator.

**Canonical (edit these):**

```
references/librarian/*.md                        shared doctrine
.agents/skills/librarian-vault-manager/SKILL.md  skill body
.agents/agents/*.md                              agent policies
```

**Generated (never edit — `scripts/sync-assets.sh` overwrites them):**

```
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

### If you customized your agents

If you edited files under `.gemini/agents/` or `.codex/agents/`, those edits
will be **overwritten** by the generator. Port them to the canonical policy in
`.agents/agents/<name>.md` and re-run `./scripts/sync-assets.sh`. Your changes
then propagate to all four harnesses instead of one.

Check what you would lose before pulling:

```bash
git diff HEAD~1 -- .gemini/agents .codex/agents
```

### Session compilation covers four harnesses

`scripts/compile-sessions.sh` now reads Claude Code and OpenCode logs in
addition to Gemini and Codex:

```bash
./scripts/compile-sessions.sh 7                      # compile the last 7 days
AI_MEMORY_HOST=claude ./scripts/compile-sessions.sh   # review with Claude Code
AI_MEMORY_DRY_RUN=dump ./scripts/compile-sessions.sh  # inspect without a model call
```

OpenCode stores sessions in SQLite (`~/.local/share/opencode/opencode.db`), so
reading its logs requires `sqlite3` on your PATH. If it is missing, OpenCode
logs are skipped with a notice and the other harnesses still compile.

### Fixed: Recent Activity Map showed "N/A" for every session

The boot hook builds a table of your last five `JRNL/AGNT/` sessions from each
log's goal. It only ever matched the inline `**Goal:** …` form, so vaults whose
logs use a `## Goal` heading with the text on the following line showed `N/A`
for every row — the map loaded but carried no information. Both formats are now
recognized. No action required; the fix applies as soon as you pull.

## Troubleshooting

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
