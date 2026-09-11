# Sharing index snapshots through Git LFS

The pre-commit hook uses MCP **2.1.0** to prepare and validate an immutable
LanceDB export after incremental indexing. It publishes one snapshot per
registered vault in
`.obsidian-vault-mcp/shared/<vault-id>/`. Receiving machines install that
snapshot without generating document embeddings.

## Daily workflow

Keep MCP sessions stopped while pulling or switching branches. On the machine
you are leaving, save your notes and run:

```bash
git add -A -- vaults/example
git commit -m "Update vault and search index"
git push
```

The commit hook updates the index, prepares the snapshot, and stages it with
your notes. On the receiving machine, run this before starting the MCP:

```bash
git pull --ff-only
```

The receive hook downloads any missing LFS payloads and installs the snapshot.
Then start the MCP and search using the existing document embeddings. Use the
same sequence when returning to the first machine. Replace `vaults/example`
with your registered vault path.

For edits and deletions to already tracked notes, `git commit -am "Update vault"`
also publishes the matching snapshot. Stage new notes with `git add` first;
Git's `-a` option does not include untracked files.

## Set up each clone

Install Node.js 20 or later and Git LFS, then run your harness setup script.
The shared setup registers the selected vault in `.obsidian-indexes.json`,
configures LFS, and installs the commit and receive hooks. Run setup with MCP
sessions stopped. Setup also installs any shared snapshot already in the clone.
Commit the registration so other clones reuse the stable vault ID, even when
their directory names differ.
The hook uses the staged registration and rejects unstaged registration edits
or removals. Staging a new registration also publishes its existing notes.
To stop sharing a vault, explicitly stage its removal from the registration.

For an existing configured vault, registration and hook installation can also
run separately. Use the vault ID already configured in the MCP:

```bash
node scripts/index-snapshots.mjs register --vault vaults/example --id YOUR_EXISTING_VAULT_ID
bash scripts/configure-index-git.sh
git add .obsidian-indexes.json .gitattributes .gitignore
```

The pre-commit hook checks that notes are fully staged, then calls the MCP's
incremental indexing operation before export. Changed notes may require an
embedding model download. If there is no live index, the MCP builds the initial
index. Incompatible indexes require explicit repair instead of an automatic
forced rebuild. Indexing and export failures block the commit.

Stage **all Markdown changes for that vault**, then commit normally:

```bash
git add -A -- vaults/example
git commit
```

The hook publishes affected registered vaults and stages their complete
snapshots, including deletions. Unrelated staged files remain staged. An
unchanged export is reused. To prepare explicitly, including a first snapshot
when no notes have changed:

```bash
bash scripts/prepare-index-snapshot.sh --vault vaults/example
git diff --cached --stat
git commit
```

Omit `--vault` to prepare every registered vault. Publication validates export
hashes and the actual staged LFS pointers before replacing Git's index.
Preparation or staging failures roll back published trees and leave the
original staging area intact. Incremental indexing can still have updated the
local live database. The MCP's export cache can also contain new output.

Rollback covers failures inside snapshot preparation and staging. If preparation
succeeds but Git later rejects the commit, for example in a `commit-msg` hook,
generated snapshot files remain in the working tree. With `commit -a`, Git
restores the prior staging area. Review and stage the complete prepared snapshot
before retrying, since `-a` does not include new database payload files:

```bash
git add -A -- .obsidian-vault-mcp/shared/YOUR_EXISTING_VAULT_ID
git commit -am "Update vault and search index"
```

## Automatic installation and recovery

Setup installs these handlers in each clone:

| Hook | Behavior |
| --- | --- |
| `pre-commit` | Incrementally index and publish affected registered vaults. |
| `post-merge` | Install shared snapshots after a successful merge or fast-forward pull. |
| `post-checkout` | Install shared snapshots after a branch checkout, switch, or linked worktree creation. File-only checkouts skip installation. |
| `post-rewrite` | Install shared snapshots after a completed rebase. Commit amendments skip installation. |

Receive hooks skip intermediate conflict and rebase states, and uncommitted
squash merges. They validate the committed snapshot, download LFS objects when
the checkout contains pointers,
and verify that its note hashes match the current vault. Already installed
snapshots are not recopied. A local marker records the installed snapshot;
checkout-related note timestamps are refreshed in local freshness metadata.

The hooks assume **MCP sessions are stopped during pulls and branch switches**.
They take the MCP writer lock, but that lock does not stop existing readers.
There is no reliable running-session detection in this implementation.
[Upstream issue #24](https://github.com/jabez007/obsidian-vault-mcp/issues/24)
tracks coordinated adoption while sessions remain active.

A receive hook runs after Git changes the checkout. An installation failure
cannot undo the pull or branch switch. The hook reports the error and leaves
the previous live database in place for that vault. Keep the MCP stopped,
resolve the reported problem, and retry explicitly:

```bash
git lfs pull
bash scripts/install-index-snapshot.sh --vault vaults/example
```

An already-up-to-date pull does not trigger `post-merge`, so use this recovery
command after a failed installation. If a branch has no shared snapshot, the
receive hook leaves its local database alone. Multiple vaults install
individually; an error in one does not undo installations already completed
for other vaults.

Receiving machines need a compatible MCP runtime and enough disk for the
shared snapshot, an installed copy, and temporary copies during replacement.
Semantic queries still need a query embedding model. Receiving a snapshot
never generates document embeddings. After cloning, run setup once because
Git does not copy local hooks into a new clone.

## Migrate a tracked live database

The new ignore rules do not remove files already tracked by Git. Register the
vault with its existing ID, run Git setup, and stage the configuration and
all note changes. Migration updates the index before preparing the export:


```bash
node scripts/index-snapshots.mjs migrate --vault vaults/example
git diff --cached --stat
git commit
```

Migration prepares the shared snapshot and stages removal of that vault's
tracked live storage in the same Git index transaction. It keeps local live
files on the publishing machine. Other clones pulling the removals should
install the new shared snapshot before restarting their MCP sessions. Legacy
`.gemini-obsidian/vaults/<id>/` entries with the same ID are also untracked;
a usable v2.1.0 live index must already exist before migration.

For separately tracked model downloads or scratch files reported by setup,
remove each exact path from tracking while retaining the local copy:

```bash
git rm --cached -- 'path/to/reported/file'
```

Setup removes old default ONNX LFS rules only after matching models are no
longer tracked. Rerun setup and stage `.gitattributes` after those removals.
Clones pulling model removals may need to download their models again.

## Storage policy

| Files | Policy |
| --- | --- |
| `shared/<id>/lancedb/` | Git LFS; use the MCP's complete validated export inventory. |
| `shared/<id>/{file-hashes,index-metadata,schema-version,snapshot}.json` | Ordinary Git, committed with the matching database. |
| `.obsidian-indexes.json` | Ordinary Git; maps vault paths to stable IDs. |
| `.obsidian-vault-mcp/vaults/` | Ignored live databases, locks, and MCP export generations. |
| `.gemini-obsidian/vaults/` | Ignored legacy live storage. |
| `.obsidian-vault-mcp/.transactions/` | Ignored publication scratch space. |
| `node_modules/`, MCP ONNX downloads and `.onnx_data` sidecars | Ignored local runtime and model files. |

LFS tracks database payload, not MCP executables. The default attributes are:

```gitattributes
.obsidian-vault-mcp/**/*.lance filter=lfs diff=lfs merge=lfs -text
.obsidian-vault-mcp/**/*.lance/** filter=lfs diff=lfs merge=lfs -text
```

Internal Lance version manifests and search indexes remain part of the
export. Do not prune them with filename-based ignore rules. The MCP owns
compaction, retention, and database validation; the template copies its
validated inventory. This does not guarantee the smallest possible database.
Only one export generation per vault enters each Git commit. Local MCP export
generations can still accumulate and require separate cache management.

## Line endings and existing checkouts

The MCP hashes the files it reads from disk. Those bytes must match both the
staged notes and the receiving checkout. The template's `.gitattributes` keeps
vault Markdown, registration, shared JSON metadata, and hook scripts at LF,
including in clones with `core.autocrlf=true`. Database files retain their
binary LFS attributes. Setup adds the LF rules from
`scripts/index-snapshot-attributes.gitattributes` while preserving custom rules.
When merging template updates, retain both the LF rules and your LFS rules.

Staged additions, edits, and deletions of `.gitattributes` trigger validation
even when no notes change. The hook checks effective staged and working rules
for affected registered notes, snapshot metadata, tracked database payloads,
and scripts covered by the LF policy. Root rules apply across the repository;
nested rules apply within their directories. A valid attribute-only commit
does not index, export, or require unstaged note edits to be staged.

Keep shared attribute rules in `.obsidian-vault-mcp/shared/.gitattributes` or
an ancestor directory. A vault's `shared/<id>/` directory contains only the
validated snapshot inventory, so adding `.gitattributes` inside it is rejected.

Existing files can still contain CRLF, and editors can write new CRLF content.
Publication checks for this before indexing and reports the affected file.
It also rejects attribute overrides that could change the bytes during Git
staging or checkout. Configure your editor to save vault Markdown as LF.

To convert an existing checkout, stop the MCP and run:

```bash
node scripts/index-snapshots.mjs normalize-text --vault vaults/example
bash scripts/configure-index-git.sh
git diff
git add .gitattributes .obsidian-indexes.json
git add --renormalize -- vaults/example
```

Omit `--vault` to convert all registered vaults. The converter replaces only
CRLF with LF in visible Markdown, registration, and snapshot JSON, including
local companion metadata. It checks shared metadata against the snapshot
inventory and takes the live database writer lock before changing notes or
local metadata. It leaves Git staging unchanged. Review and stage all intended
note changes, including new files, before committing. Renormalization stages
the complete tracked notes, so review any previously partial staging first.

On a publishing machine, the next commit updates the index and exports a
matching snapshot. Notes previously indexed with CRLF may need new embeddings.
On a receiving machine with an LF snapshot, conversion can repair a CRLF
checkout without generating embeddings. Retry installation after conversion:

```bash
bash scripts/install-index-snapshot.sh --vault vaults/example
```

Setup may report an installation mismatch during migration if the existing
snapshot describes the old note bytes. Publish an updated snapshot on a
machine that can index those notes, then pull it on the receiving machines.
If the shared inventory itself describes CRLF metadata, the converter refuses
to invalidate it. That snapshot needs to be republished from an LF vault.
Substantive note edits still require a matching snapshot.

## Hook behavior and limits

The default local policy is `required`. The hook checks staged registration
consistency on every commit. It publishes registered vaults for staged Markdown,
registration, snapshot, or live-storage changes.
Attribute changes also trigger the separate validation described above.
Unregistered notes and unrelated files skip preparation. Explicit `prepare`
and `migrate` always validate and publish, regardless of `snapshotPolicy`.
They honor `snapshotAutoIndex`, just like pre-commit.

```bash
git config --local obsidian.snapshotPolicy required
# Default: update the live index before preparing a snapshot.
git config --local obsidian.snapshotAutoIndex true
# Default: install snapshots after pulls and branch changes, and during setup.
git config --local obsidian.snapshotInstall auto
# Optional maximum total payload size per vault, in bytes:
git config --local obsidian.snapshotMaxBytes 104857600
# Explicitly allow note commits without publishing a matching snapshot:
git config --local obsidian.snapshotPolicy off
```

On a machine where indexing must be manual, set `snapshotAutoIndex` to `false`.
Publication then requires an already-current live index. For note-only commits
that a capable machine will index later, set `snapshotPolicy` to `off`. Such
commits can leave shared snapshots behind the notes, and receiving installation
will reject a mismatch. To disable automatic installation, set
`snapshotInstall` to `off`; the explicit install command remains available.

The earlier stub's `warn` policy is no longer supported; change it to
`required` or `off`. Git's `--no-verify` also bypasses the hook. These are local
checks, so a bypass can leave shared snapshots behind the committed notes.

All indexable Markdown content must match the commit's staging area, including
new and deleted notes. Normal commits and `git commit -a` are supported. For
`-a`, the hook updates Git's pending index, which Git commits or discards after
the hook finishes. Partial note staging, visible vault symlinks, path-limited
commits such as `git commit --only` or `git commit path`, and unrelated alternate
Git indexes are rejected for publication. Use `git add` followed by `git commit`
when a command is rejected. Register each vault separately for commits affecting
multiple vaults.

The adapter pins `@jabez007/obsidian-vault-mcp@2.1.0`, schema 3, and LanceDB
0.27.2. Harness plugins should run a compatible MCP version. For a preinstalled
or offline CLI, set `OBSIDIAN_SNAPSHOT_MCP` to a single executable launcher
path; the adapter passes CLI arguments directly, without shell evaluation.

Publication and installation errors trigger rollback. Forced termination can
leave lock files and transaction backups. Before removing an abandoned lock, verify its owner has
stopped and inspect the transaction directory; preserve backups if recovery
is needed. Do not run competing manual file operations during publication or
installation.

### Existing hooks and linked worktrees

The installer supports linked worktrees and leaves `core.hooksPath` unchanged.
It installs missing hooks and combines stock Git LFS checkout and merge hooks
with the snapshot dispatcher. The original Git LFS pre-push and post-commit
handlers remain in place. Rerun `scripts/configure-index-git.sh` to configure
LFS and these combined hooks together. A separate `git lfs install` can report
the combined hooks as conflicts; do not force-overwrite them.

Custom hooks and custom hook directories are preserved. Setup reports hooks
that need manual integration. Use your hook manager to run these commands,
passing each hook's arguments and propagating failures:

```bash
# pre-commit:
bash "$(git rev-parse --show-toplevel)/scripts/hooks/pre-commit.sh"
# post-merge, after the existing Git LFS handler:
bash "$(git rev-parse --show-toplevel)/scripts/receive-index-snapshot.sh" post-merge "$@"
# post-checkout, after the existing Git LFS handler:
bash "$(git rev-parse --show-toplevel)/scripts/receive-index-snapshot.sh" post-checkout "$@"
# post-rewrite, after any existing consumer of Git's rewritten-commit list:
bash "$(git rev-parse --show-toplevel)/scripts/receive-index-snapshot.sh" post-rewrite "$@"
```

Keep the standard Git LFS handlers for pre-push, post-commit, post-checkout,
and post-merge. `git lfs update --manual` prints their integration instructions.
With a custom hook manager, run the explicit snapshot install command once
after initial setup. The dispatchers read handlers from the current worktree,
so pulling template updates updates their behavior. Older checkouts without
the receiving handler skip installation.

Snapshot preparation reduces obsolete data in future commits. It cannot
reclaim previously uploaded GitHub LFS objects, and changed payloads still
consume additional historical storage. See
[GitHub's LFS removal guidance](https://docs.github.com/en/repositories/working-with-files/managing-large-files/removing-files-from-git-large-file-storage).
