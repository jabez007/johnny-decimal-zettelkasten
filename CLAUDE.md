# Claude Code Guidance

The repository guidance for every harness lives in [`AGENTS.md`](AGENTS.md).
Read it first — it defines the repo scope, vault rules, permanent-note format,
and workflow that apply here.

## Claude-specific notes

- Specialist agents are in `.claude/agents/`. They are **generated** from
  `.agents/agents/*.md` by `./scripts/sync-assets.sh` — edit the canonical
  source, not the generated copy.
- The `librarian-vault-manager` skill in `.claude/skills/` is likewise
  generated from `.agents/skills/` and `references/librarian/`.
- `.claude/settings.json` registers a `SessionStart` hook that restores Agent
  Memory (procedural rules plus a map of recent `JRNL/AGNT/` sessions).
- Vault access goes through the `obsidian-vault-mcp` MCP server. Its tools are
  namespaced `mcp__obsidian-vault-mcp__obsidian_*`.

Run `./.claude/setup-environment.sh` to install the MCP plugin and configure a
vault.
