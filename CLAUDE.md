# Claude Code Guidance

@AGENTS.md

The import above loads [`AGENTS.md`](AGENTS.md), the repository guidance every
harness shares. It defines the repo scope, vault rules, permanent-note format,
and workflow that apply here.

## Claude-specific notes

- Specialist agents are in `.claude/agents/`. They are **generated** from
  `.agents/agents/*.md` by `./scripts/sync-assets.sh` — edit the canonical
  source, not the generated copy.
- The `librarian-vault-manager` skill in `.claude/skills/` is likewise
  generated from `.agents/skills/`.
- Vault access goes through the `obsidian-vault-mcp` plugin. Claude Code names
  its tools `mcp__plugin_obsidian-vault-mcp_obsidian-vault-mcp__obsidian_*`.

Run `./.claude/setup-environment.sh` to install the MCP plugin and configure a
vault.
