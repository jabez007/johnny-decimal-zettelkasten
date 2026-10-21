# Run Hindsight alongside the vault

[Hindsight](https://github.com/vectorize-io/hindsight) is an optional memory
provider for agents. It retains sessions and recalls them later. The knowledge
vault does not depend on it. This repository contains no Hindsight
configuration, and nothing in it calls Hindsight. Everything in this guide is
user-level configuration on each machine, which you can add or remove without
touching the vault.

The two systems hold different things:

| | Hindsight | Knowledge vault |
| :--- | :--- | :--- |
| Holds | What agents picked up while working with you: sessions, repository facts, preferences | What you decided to keep |
| Written by | The integration, automatically | You, or an agent after you approve a proposal |
| Stored in | A Hindsight bank on a server or a local daemon | Markdown in Git |
| Authority | A lead to verify | Curated, but check it against current sources |

## Follow four rules

1. Hindsight never writes to the vault. Knowledge moves from recall to a note
   only through the [promotion workflow](../references/librarian/knowledge-promotion.md),
   with your approval. Recall is a lead to verify, not a source to cite.
2. Exclude the vault repository from Hindsight ingestion, as described below.
3. Hindsight builds knowledge pages by summarizing a bank. Those pages are
   generated text, not curated knowledge. Verify a page's claims before you
   promote any of them.
4. A bank name does not control access. The Hindsight README describes bank
   isolation but no per-bank permissions, so anyone holding the server's API
   token can reach every bank on it. Put work that must stay separate, such as
   client work, on a separate server or token.

## Set up the local machine

This setup covers Claude Code, Codex CLI, OpenCode, and pi, used from Neovim or
a terminal. The integration does not support Gemini CLI.

Install the integration for the CLIs you use:

```bash
npx @vectorize-io/hindsight-coding-agents install claude-code codex opencode pi
```

The installer asks where memory lives: Hindsight Cloud, a server you run, or a
local daemon. It writes only user-level files: hooks, MCP registrations, and
companion skills, such as hooks in `~/.claude/settings.json` and
`~/.codex/hooks.json`, a plugin entry in `~/.config/opencode/opencode.json`, and
an extension entry in `~/.pi/agent/settings.json`. It backs up each existing
file it changes as `<file>.hindsight-backup`. Configuration lives in one file,
`~/.hindsight/coding-agent.json`. `HINDSIGHT_CONFIG` moves it, and
`HINDSIGHT_API_URL` and `HINDSIGHT_API_TOKEN` supply connection settings.

The integration attaches to each CLI, not to Neovim. A CLI that you run in a
Neovim terminal, or that a Neovim plugin starts as a process, gets memory. A
Neovim plugin that calls a model API directly does not. Hindsight picks the
bank from the Git repository where the session starts, so start each session
from the project you are working on.

## Exclude the vault repository

By default, the integration remembers every repository. In each one it retains
session transcripts (`retainSessions`), ingests commit messages (`gitIngest`),
seeds a new bank from Git history (`autoSeed`), and surveys the codebase
(`codebaseSurvey`). Turn all of that off for the repository that holds your
vault. Pick one of these options in `~/.hindsight/coding-agent.json`.

To turn memory off for the vault repository, disable its bank. Copy the bank ID
from the session banner that appears when a session starts in the vault
repository. Take the whole ID from the banner, because a custom
`bankIdTemplate` changes it. Exit that first session without working in it, or
use opt-in mode below, which needs no bank ID.

```jsonc
{
  "banks": {
    "<bank ID from the session banner>": { "disabled": true }
  }
}
```

To turn memory on only where you ask for it, use opt-in mode. Everything outside
`optInPaths` is inert, so a new vault clone stays excluded with no further
setup. Choose this option when your vault lives under the same folder as your
code:

```jsonc
{
  "optInOnly": true,
  "optInPaths": ["~/source/repos/project-a", "~/source/repos/project-b"]
}
```

To keep recall in the vault repository but store nothing from it, override the
ingestion settings for its bank:

```jsonc
{
  "banks": {
    "<bank ID from the session banner>": {
      "retainSessions": false,
      "gitIngest": "none",
      "autoSeed": false,
      "codebaseSurvey": false
    }
  }
}
```

Do not pass `--import-conversations` to `install` for a vault repository. That
flag imports past transcripts into the bank.

### Watch for the indirect path

When an agent in another repository reads a vault note through the MCP, the
note's text becomes part of that session's transcript. With `retainSessions` on,
Hindsight retains that transcript in the other repository's bank. If you
consult sensitive notes from a project, set `"retainSessions": false` for that
project's bank, or consult those notes from a session in the vault repository.

## Set up a separate Hermes Agent machine

Hermes Agent has its own Hindsight plugin:

```bash
hermes plugins install hindsight
hermes memory setup          # select hindsight
hermes memory status         # expect hindsight and "Status: available"
```

Each Hermes profile reads `$HERMES_HOME/hindsight/config.json`
(`~/.hermes/hindsight/config.json` for the default profile):

```json
{
  "mode": "local_external",
  "api_url": "http://memory-host.lan:8888",
  "bank_id_template": "hermes-{profile}",
  "auto_recall": true,
  "auto_retain": true
}
```

- `mode` is `cloud`, `local_embedded`, or `local_external`. To share one server
  with the local machine, use `local_external` with that server's URL, or use
  `cloud` with both machines.
- `bank_id` defaults to `hermes`. The template `hermes-{profile}` gives each
  profile its own bank.
- Keep Hermes banks separate from `coding-agent::*` banks unless you want
  Hermes to share coding memory.
- To avoid two memories, turn off Hermes's built-in memory with
  `hermes config set memory.memory_enabled false` and, optionally,
  `hermes config set memory.user_profile_enabled false`.

The Hermes plugin has no setting that excludes a directory or a tool from
retention. If Hermes on that machine can read a vault clone, it retains every
turn, including note text it reads. Either keep the vault out of Hermes's
reach, or use a separate Hermes profile with `"auto_retain": false` for vault
work.

## Choose a bank layout

| Bank | Written by | Holds |
| :--- | :--- | :--- |
| `coding-agent::<repo>` | Local CLIs | One bank per code repository, shared by every CLI |
| `hermes-<profile>` | Hermes Agent | Hermes conversations, one bank per profile |
| None | The vault repository | Excluded from ingestion |

The default template, `coding-agent::{gitProject}`, gives all local CLIs one
shared bank per repository. Use `"bankIdTemplate": "{harness}-{gitProject}"` to
give each CLI its own bank instead. For client work, use a `paths` entry that
points that folder at a different server or token. A separate bank name alone
does not isolate it.

## Remove Hindsight

```bash
npx @vectorize-io/hindsight-coding-agents uninstall all
```

`uninstall` removes what `install` added. On Hermes, run `hermes memory setup`
and choose another provider. Retained memory stays on the server until you
delete its bank. The vault needs no change in either case.

## Sources

- [Hindsight](https://github.com/vectorize-io/hindsight)
- [Hindsight coding-agents integration](https://github.com/vectorize-io/hindsight/tree/main/hindsight-integrations/coding-agents)
- [Hermes Agent Hindsight plugin](https://hermes-agent.nousresearch.com/docs/plugins/hindsight)
