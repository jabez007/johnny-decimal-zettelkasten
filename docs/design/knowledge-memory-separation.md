# Separating the knowledge vault from agent memory

Status: implemented on branch `refactor/personal-knowledge-system`.

## Summary

The template had two jobs. It managed a personal knowledge vault, and it acted
as the long-term memory of every coding agent that opened the repository. The
second job now belongs to a separate memory provider such as Hindsight, which
has its own integrations for each harness. This refactor removes the vault's
agent-memory machinery and keeps everything that serves personal knowledge.

The vault is a library. Agents can search it, cite it, and propose additions,
but they no longer write their own session logs or behavioral rules into it.

## Before

```text
harness start ──► SessionStart hook ──► scripts/agent-memory-context.sh
                                          │ reads ~/.obsidian-mcp.config.json
                                          │ lists JRNL/AGNT/*.md
                                          ▼
                              injected "Boot/Shutdown SOPs"
                                          │
session end   ◄── agent writes JRNL/AGNT/<timestamp>.md and AGNT/ rules
                  agent appends a staff report to the human daily note

scripts/compile-sessions.sh ──► reads ~/.claude, ~/.codex, ~/.gemini, OpenCode DB
                               ──► runs a model in yolo/acceptEdits mode
                               ──► writes AGNT/ rules
```

Every session in this repository received instructions to write to the vault.
The Gemini setup installed the same hook globally, so Gemini sessions in any
directory did too. The context script read whichever vault the MCP config named,
which is how a session in this template restored history from a different
repository's vault.

## Responsibility inventory

| Component | Responsibility it actually served | Class | Action |
| :--- | :--- | :--- | :--- |
| Johnny Decimal and Zettelkasten doctrine, `references/librarian/` | Note structure and linking | Keep | Rewrite the `AGNT` boundary section as a knowledge-versus-memory boundary |
| `librarian-vault-manager` skill and the eight agent policies | Deliberate vault maintenance | Keep | Remove `AGNT` system knowledge; add consult and promotion rules |
| `scripts/sync-assets.sh` | One canonical source, four harness formats | Keep | Stop generating the compiler wrapper and the Codex hook block |
| Setup scripts, `configure-vault.sh` | MCP install, vault selection, index Git config | Keep | Remove hook installation; Gemini setup removes the hook it installed earlier |
| Index snapshot hooks, `index-snapshots.mjs`, Git LFS | Share the LanceDB index | Keep | No change. They never touched agent memory |
| `daily-reviewer` | Review human daily notes, and compile CLI transcripts | Refactor | Keep the daily-note review; drop transcript compilation, `bash`, and `write` |
| `librarian` "Crystallization" responsibility | Suggest filing chat insights into the vault | Refactor | Replace with the Discover, Propose, Review, Publish workflow |
| `_SYS/log.md` knowledge log | Record of approved knowledge operations | Keep | It records curated changes, not sessions |
| `scripts/agent-memory-context.sh` | Inject SOPs and a recent-session map | Retire | Deleted |
| `.claude/hooks/session-start.sh`, `.codex/hooks/session-start.sh`, `.claude/settings.json` hook, Codex `[[hooks.SessionStart]]` | Deliver that context | Retire | Deleted. They did no vault initialization or index work |
| Gemini global `agent-memory-boot` hook | Deliver that context in every directory | Retire | Setup no longer installs it and removes an earlier install |
| `scripts/compile-sessions.sh` and its skill wrappers | Mine CLI transcripts into `AGNT/` rules | Retire | Deleted. A memory provider retains sessions natively |
| `AGNT/` rules, `JRNL/AGNT/` logs in user vaults | Agent procedural and episodic memory | Retire as a convention | Content stays where it is until the owner runs the migration |
| `JDEX_AGNT.base` and the example vault's `AGNT/` sample | Demonstrate the convention | Retire | Removed from the template's sample vault |
| Daily-note "Agent Staff Report" | Agents logging into the human journal | Retire | No longer instructed anywhere |
| Optional memory-provider usage | Recall prior agent experience | Optional | Documented in `docs/hindsight-coexistence.md`; no code |

Nothing in the index snapshot path read or wrote `AGNT/` or `JRNL/AGNT/`, so the
snapshot hooks need no change. The only overlap is that the RAG index contained
those notes, because they were ordinary Markdown in the vault.

## After

```text
coding harness ──► memory provider integration (optional, configured outside this repo)
       │
       └──► obsidian-vault-mcp ──► vault (read; write only after explicit approval)

vault repo ──► Git, Git LFS index snapshots, Obsidian
```

Dependency rules:

- The vault, its scripts, its setup, and its tests do not reference a memory
  provider. A machine with only Obsidian, Node.js, and the MCP is complete.
- A memory provider does not read the vault. Its coding-agent integration should
  exclude the vault repository from automatic ingestion.
- Agents may use both. Memory recall never authorizes a vault write.

## Reused pieces

- `obsidian_create_note` and the other MCP write tools already enforce the vault
  boundary, refuse to overwrite, and re-index on write. The promotion workflow
  uses them as the publish step, so it needs no new code.
- The librarian approval gates already exist. Promotion is written as doctrine
  in `references/librarian/knowledge-promotion.md` and referenced by the skill
  and the agents.
- The MCP indexer skips hidden paths. The migration archives legacy content into
  `<vault>/.archive/agent-memory/` with `git mv`, which removes it from search
  and from Obsidian while keeping it in Git history.

## Migration risks

| Risk | Mitigation |
| :--- | :--- |
| Legacy notes contain personal knowledge worth keeping | `inventory` lists candidates and nothing moves until `archive --apply` |
| Human notes embed or link legacy logs | `inventory` reports inbound links; `archive` refuses while any exist unless told otherwise |
| Untracked logs lose history when moved | `archive` refuses untracked or modified files |
| A global Gemini hook keeps telling agents to write logs | Gemini setup removes it; `inventory` reports any that remain |
| Forks keep the old Claude hook | Pulling this change deletes `.claude/settings.json` and the hook scripts |
| Secrets in session logs | `inventory` flags credential-shaped lines; the promotion doctrine forbids publishing them |
| Stale index entries after archiving | The pre-commit snapshot hook re-indexes; `obsidian_rag_index` does it on demand |

## Implementation sequence

1. This design note.
2. Remove the hooks, the context script, the session compiler, and their
   generated wrappers. Update `sync-assets.sh`, the setup scripts, and tests.
3. Refocus the doctrine, the skill, and the agent policies. Regenerate assets.
4. Add the promotion doctrine and wire it into the librarian and the skill.
5. Add the migration tool and guide, the usage guide, and the coexistence guide.
   Rewrite the README and remove the sample `AGNT` content.
6. Extend the test harness and run it.

`obsidian-vault-mcp` needs no change.
