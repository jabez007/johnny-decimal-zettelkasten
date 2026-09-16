# Set up a vault and global access

Install Git, Git LFS, Node.js 20 or later, Python 3.9 or later, `jq`, and the
agent CLI you want to use. Clone this template into the repository that will
own your vault.

Run setup once for each harness you use. Choose the same vault name each time:

```bash
./.claude/setup-environment.sh --vault my-notes
./.codex/setup-environment.sh --vault my-notes
./.opencode/setup-environment.sh --vault my-notes
./.gemini/setup-environment.sh --vault my-notes
```

Each command can also be invoked by absolute path from another directory.
Use `--check` to validate the selection and global destinations without installing
plugins, writing configuration, or creating a vault.
Setup creates `vaults/my-notes/` with starter indexes, a daily-note template,
and Obsidian daily notes under `JRNL/`. It does not copy sample preferences or
session history from `vaults/example/`. Open `vaults/my-notes/` in Obsidian.

Setup preserves existing vault content. A failed initial scaffold can be retried
without overwriting files created or edited in the meantime. Stop running MCP
sessions before setup, then restart your harness to load its configuration.

Setup indexes the vault and checks that semantic retrieval returns a note.
The first run can download the embedding model. Use `--skip-index` to defer the
final indexing and retrieval check; setup reports that search remains unverified.
Creating starter notes can itself trigger the MCP's automatic indexing.

Without `--vault`, setup reuses a selected vault in this checkout. A fresh
unattended setup defaults to `example`. If another repository's vault is already
selected, unattended setup stops before changing plugin registrations or the
vault selection. Use `--vault NAME` to make an intentional switch. All installed
harnesses use the shared MCP default, so switching it affects new sessions in
other projects too. Environment variables can override that default; use the
doctor command to check what the MCP actually selects.

## Check access from another project

Restart the harness in an unrelated repository. Ask:

> Use jd-vault-research to find my vault index and explain which notes you read.

Then ask it to record a short entry in today's daily note. Research and journal
capture are available globally. The librarian and its management agents remain
local to the vault repository.

Run the diagnostic for the harness you installed:

```bash
python3 /path/to/vault-repo/scripts/doctor.py --harness opencode
```

The diagnostic checks global files, registration, the MCP-selected vault, and
semantic retrieval. It does not establish which tools an already-running model
session has loaded. See [the harness smoke test](../test/harness-smoke.md) for
the final checks with authenticated CLIs.

## Review and crystallize journal captures

Start the harness from the repository that owns the selected vault. Ask the
local librarian to review journal candidates and propose permanent notes. Review
the placement, IDs, and metadata before approving structural changes.

Global agents may read every system and capture daily notes, sessions, and
candidate insights under `JRNL/`. Permanent-note edits, durable `AGNT` rules,
crystallization, merges, and restructuring belong in the owning repository.
These are template instructions. The generic Obsidian MCP remains unchanged
and does not impose Johnny Decimal rules or write restrictions.

## Update an existing clone

Bring in the template changes, then rerun setup for each harness. Existing user
instructions remain around an identifiable managed block. Existing skill files
with the template's names are replaced only if the installer owns them. OpenCode
configuration is merged without removing unrelated settings or JSONC comments.
Codex setup uses `AGENTS.override.md` when that file already takes precedence.

Gemini setup removes the old template-owned `agent-memory-boot` hook registration
and installs standing global instructions instead. It preserves other hooks.
The old hook files can remain on disk; they are no longer registered by setup.

The installer records template-owned vaults in
`~/.config/jd-vault/vaults.json`, or under `XDG_CONFIG_HOME` when set. The global
policy applies only when the MCP-selected vault matches this registry. It does
not impose the template's workflow on other Obsidian vaults.

## Installed files

| Harness | Global instructions | Global template skills |
| --- | --- | --- |
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills/jd-vault-*` |
| Codex | `~/.codex/AGENTS.md`, or an existing nonempty `AGENTS.override.md` | `~/.agents/skills/jd-vault-*` |
| OpenCode | `~/.config/opencode/AGENTS.md` | `~/.config/opencode/skills/jd-vault-*` |
| Gemini | `~/.gemini/GEMINI.md` | `~/.gemini/skills/jd-vault-*` |

The installer respects `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, and `XDG_CONFIG_HOME`
for their corresponding configuration directories. OpenCode gets a global
`obsidian-vault-mcp` registration. The other harnesses retain their native
upstream plugin or extension installation. Setup does not copy local management
agents into any global directory.

Canonical global policy and skill sources live in `references/global-vault/`.
Canonical starter assets live in `references/vault-starter/`. Update these
sources, then rerun setup to refresh installed global files. Local agent and
skill copies still come from `scripts/sync-assets.sh`.
