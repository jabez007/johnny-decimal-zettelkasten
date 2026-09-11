# Test harness

Exercises the template's setup, generation, and migration scripts in an
isolated environment.

## Running

```bash
cd test
docker compose run --rm harness           # full suite
SKIP_RAG_INDEX=1 docker compose run --rm harness   # skip the slow index test
docker compose run --rm harness bash      # interactive shell
```

If your user is not in the `docker` group, either add it once
(`sudo usermod -aG docker $USER`, then log out and back in) or prefix the
commands with `sudo`.

### Without Docker

The suite runs on any machine with Node.js 20 or later, `git`, `jq`, `sqlite3`,
`git-lfs`, `shellcheck`, and Python 3.11 or later. Point it at a throwaway HOME so it
cannot touch your real vault config or plugin state:

```bash
SANDBOX=$(mktemp -d)
env -i PATH="$PATH" HOME="$SANDBOX/home" \
  REPO_SRC="$PWD" WORK_DIR="$SANDBOX/repo" \
  bash test/run-tests.sh
```

### Snapshot hook tests only

The snapshot tests require Node.js, Git, Git LFS, and Python:

```bash
python3 test/test-index-hooks.py
```

They use temporary repositories and isolated Git configuration. Most cases
use a deterministic MCP fixture to test rollback, partial staging, multiple
vaults, stable IDs, LFS pointers, migration, automatic indexing, merge and rebase
pulls, branch switches, and installation failures. Regression cases cover staged
registration removals, CRLF migration, LF checkouts with `core.autocrlf=true`,
conflicting attributes, and actual `git commit -am` success and rollback in
ordinary repositories and linked worktrees.
Attribute-only cases cover root and nested rules, deletion of required rules,
staged rules differing from working rules, and removal of LFS filters. Valid
attribute changes must pass without the MCP or changes to unstaged notes.

To also test a real release, set `MCP_SNAPSHOT_RELEASE` to the unpacked MCP
2.1.0 package directory with its dependencies installed:

```bash
MCP_SNAPSHOT_RELEASE=/path/to/package python3 test/test-index-hooks.py
```

That test seeds a real LanceDB with synthetic vectors, invokes the published
CLI, pushes to a local bare repository through Git LFS, clones it, and
installs the snapshot through setup in an `autocrlf=true` clone. It then indexes
a new empty note during `git commit -am` and installs the updated snapshot
automatically on pull before running vector and full-text queries. It downloads
no embedding model and contacts no external Git remote. The full harness resolves the npm
package and requires this test, even when `SKIP_RAG_INDEX=1`.

## In CI

`.github/workflows/test.yml` runs the whole suite on every push and pull
request, without Docker — a runner is disposable, so the isolation Docker
provides locally is redundant there. A cold run takes about three minutes,
nearly all of it npm fetching onnxruntime.

## Safety

- The repository mounts **read-only**; the suite works on a copy at
  `/work/repo`, so a run cannot modify your working tree.
- The container has its own `HOME`, so `~/.obsidian-mcp.config.json`, plugin
  registrations, and session logs stay inside the container.
- No vault note content is modified. The one file the suite writes into the
  example vault (a synthetic session log) is removed afterwards.

## What it covers

| Section | Checks |
| :--- | :--- |
| 1. Static | shellcheck across all scripts; JSON and TOML parse; 8 agents registered in `.codex/config.toml` |
| 2. Generation | `sync-assets.sh` runs, is idempotent, and matches what is committed (the CI drift gate); doctrine identical across harnesses; correct MCP prefix per harness; no unsubstituted `{{MCP_PREFIX}}` |
| 3. MCP server | `obsidian_set_vault` writes the config; `obsidian_list_notes` reads the vault; `obsidian_rag_index --force_reindex` builds an index under `.obsidian-vault-mcp/`; `obsidian_rag_query` returns results with a rendered relevance score |
| 4. Agent memory | Context emits SOPs and the Recent Activity Map; goal extraction for **both** the inline `**Goal:**` and `## Goal` heading forms; both session hooks emit valid `SessionStart` JSON |
| 5. Session compiler | Extracts Claude Code turns and filters `tool_result` noise; extracts OpenCode SQLite turns; handles an empty log set; rejects an unknown `AI_MEMORY_HOST` |
| 6. Migration | `migrate-v2.sh` runs non-interactively, rewrites LFS globs, and is re-runnable |
| 7. Setup gates | Each `setup-environment.sh` fails fast when its CLI is missing, tested with a restricted PATH so the result does not depend on what is installed |
| 8. Snapshot hooks | Publication and rollback with real Git/LFS; incremental indexing; automatic installation after pull, rebase, and branch switch; migration; published MCP 2.1.0 export → LFS push/clone → vector and full-text queries without reindexing |

## What it does not cover

Running actual agent sessions. That needs authenticated CLIs, so the suite
stops at verifying each setup script's dependency gate. The MCP server itself
is exercised for real, since its CLI mode needs no credentials.

## Notes

- The first run downloads the ~90MB embedding model. The Docker image warms the
  npx cache at build time, but the model downloads on first index.
- Set `SKIP_RAG_INDEX=1` to skip indexing when iterating on other sections.
