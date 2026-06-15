# Johnny Decimal Zettelkasten Repository Guidance

## Repo Scope

- The actual Obsidian vaults live under `vaults/<vault-name>/`, not at the repository root.
- `vaults/example/` is the sample vault and the default target used by the setup scripts.
- Use the repository root for shared automation, docs, and setup. Use a vault directory for note operations.
- Shared doctrine belongs in `references/librarian/`.
- Codex-specific durable behavior belongs in `AGENTS.md` and `.codex/agents/`. Gemini-specific behavior belongs in `.gemini/`.
- The shared Obsidian MCP backend comes from the `jabez007/gemini-obsidian` fork and is installed globally per host: Gemini via the Gemini extension system, Codex via the Codex plugin system.
- The intended Codex specialist agent set mirrors Gemini: `librarian`, `daily-reviewer`, `vault-auditor`, `vault-cleaner`, `vault-scaffolder`, `vault-synthesizer`, `source-distiller`, and `flashcard-generator`.

## Vault Rules

- Use `gemini-obsidian` MCP tools for vault reads and writes when they are available.
- Treat `AGNT/` as agent procedural memory only. Do not store user domain facts there.
- Treat `JRNL/` as transient capture and session history. Evergreen `SYS.AC.ID` notes are authoritative.
- Follow Johnny Decimal ACID notation: `SYS.AC.ID`, with hexadecimal area/category/ID ranges.
- Reserve `00` for indexes. `SYS.00.00.md` is the system index and `00.00.md` is the vault root index.

## Permanent Notes

- One claim per note, with a declarative title.
- Include YAML frontmatter at the top with required core fields `entities`, `communities`, and `status`. Add `aliases` and `tags` when they improve discoverability or actionable intent.
- Put a system-index wikilink immediately after the frontmatter.
- Use contextual wikilinks in sentences. Do not add bare "see also" link dumps.

## Workflow

- Proposal-first for structural vault changes: suggest placement, IDs, and metadata before bulk edits.
- Confirm which vault under `vaults/` you are operating on when the target is ambiguous.
- Prefer updating existing evergreen notes over creating near-duplicates.
- Keep machine-facing logs and procedural rules traceable back to `JRNL/AGNT/` session notes.
- At the start of significant work, check for relevant AGNT procedural rules and review recent `JRNL/AGNT/` logs when the task appears to continue earlier work.
- If the user says `continue` or `resume`, assume prior session context matters and look for the most recent relevant `JRNL/AGNT/` log unless they specify otherwise.
- Before concluding substantial work, preserve agent context in `JRNL/AGNT/` and crystallize durable new procedural rules into `AGNT/` when warranted.
