# Knowledge lifecycle and proposal review

Status: v0.5. Phase 1 is implemented; phases 2 and 3 are not. Date: 2026-10-23.

Targets: `jabez007/johnny-decimal-zettelkasten` and
`jabez007/obsidian-vault-mcp`.

Baseline: PR #14, "Separate the knowledge vault from agent memory", released
as v3.0.0, and `obsidian-vault-mcp` v2.3.0.

## Changes from v0.4

- Phase 1 is implemented.
  [`references/librarian/proposal-queue.md`](../../references/librarian/proposal-queue.md)
  defines the records, states, and checks. `scripts/proposal-queue.mjs` lists
  and checks the queue, and six agents gained queue duties.
- Source records drop `content_sha256`. A claim cites only an excerpt stored
  in the record, and Git versions the record.
- Proposal records drop `base_sha256`. The agents that write proposals have no
  shell to compute a hash, so each edit names the exact text it replaces, and
  that text must occur once in the target.
- Closed proposals stay in `.proposals/` with a terminal state. The `closed/`
  folder is gone.
- The review Base moves to phase 2, because Obsidian does not show
  dot-folders.
- Section 6 defines how an agent finds queued proposals.
- Section 7 defines the approval record the phase 3 publisher needs.

## 1. Decision

Extend the Discover, Propose, Review, Publish process from PR #14 into a
lifecycle that keeps sources and proposals between sessions. This extends the
personal knowledge system. Johnny Decimal, Zettelkasten, and the separation of
agent memory into Hindsight stay as they are.

The main boundary runs between this template, which knows the workflow, and
the MCP server, which works for any Obsidian vault:

| Concern | Owner | What it knows |
|---|---|---|
| Source capture and lifecycle rules | `johnny-decimal-zettelkasten` | The lifecycle |
| Proposal structure, evidence, review state | `johnny-decimal-zettelkasten` | The proposal format |
| Johnny Decimal IDs and note structure | `johnny-decimal-zettelkasten` | Local conventions |
| Approval, publication, audit | `johnny-decimal-zettelkasten` or a separately installed companion | Publication rules |
| Read, search, edit, and link tools | `obsidian-vault-mcp` | Paths and documents only |
| Ignore rules, index and snapshot correctness | `obsidian-vault-mcp` | Paths and patterns only |

`obsidian-vault-mcp` must not encode source or proposal folders, `SYS.AC.ID`,
review states, or publication frontmatter. It provides generic path-based
tools, and the vault template supplies the policy and configuration.

### Terms

- **Source:** a journal entry or captured material, such as a web page,
  transcript excerpt, or file. Capturing a source does not make it accepted
  knowledge.
- **Proposal:** a reviewable change that creates or revises one curated note.
- **Curated note:** an owner-accepted Johnny Decimal and Zettelkasten note,
  including notes the owner wrote directly without any proposal.

Curated means accepted into the owner's knowledge base, not certain. A note
can still record uncertainty in its claims.

### Background

v0.1 and v0.2 called these layers Bronze, Silver, and Gold, after the
medallion architecture of data lakehouses. The analogy is loose. In a
lakehouse, each layer is derived from the one below by a repeatable
transform, so Silver can be rebuilt from Bronze. Here a proposal is a pending
change, not a refined copy of a source, and many curated notes never pass
through either earlier stage. The workflow is closer to a pull request. Plain
names also keep agents from reading "promote Bronze to Silver" as "every
capture should become a proposal", which the non-goals rule out.

## 2. Baseline

PR #14 made the vault a reference library instead of agent memory.
`references/librarian/knowledge-promotion.md` defines Discover, Propose,
Review, Publish. Hindsight is optional, lives outside the vault, and never has
authority to change it.

Facts about `obsidian-vault-mcp` v2.2.0 and later that this design depends on:

- Search indexes lowercase `.md` files outside hidden files and directories.
  An optional `.obsidian-mcpignore` at the vault root narrows that set
  further. Section 5 describes the file.
- One eligibility rule covers listing, keyword search, backlinks, broken
  links, RAG indexing, writes, moves, and snapshot preparation.
- Note tools read and write hidden paths by name. `obsidian_create_note` and
  `obsidian_read_note` work on `.proposals/P-1.md`, and
  `obsidian_list_notes` and `obsidian_search_notes` never return it.
- Index metadata and snapshot manifests record a fingerprint of the ignore
  rules. Section 5 lists what is still open.

[PR #15](https://github.com/jabez007/johnny-decimal-zettelkasten/pull/15)
moved the template to 2.2.0, and
[PR #18](https://github.com/jabez007/johnny-decimal-zettelkasten/pull/18)
moved it to 2.3.0. The snapshot hook passes the staged ignore file to the MCP server and
republishes a vault's snapshot when only the ignore file changes. It refuses
to publish when the rules exclude any note, because snapshot installation
still requires every working note to be in the snapshot.

## 3. Goals, non-goals, and invariants

### Goals

1. Keep sources and their provenance without making a permanent note for
   every observation.
2. Keep proposed changes across sessions, tools, and machines.
3. Prefer amending an existing note over creating a near-duplicate.
4. Keep Obsidian review, direct editing by the owner, and plain Markdown and
   Git working.
5. Keep sources and pending proposals out of default RAG and keyword search.
6. Keep untrusted source text, which can contain injected instructions, out
   of the results an agent gets from ordinary queries.
7. Keep incremental indexing and Git LFS snapshots correct when ignore rules
   change.
8. In the enforced mode, tie each agent-initiated publication to one exact
   proposal revision that the owner approved.
9. Keep Johnny Decimal usable when Hindsight and every agent are offline.
10. Keep `obsidian-vault-mcp` usable by any Obsidian vault, including one
    with no lifecycle at all.

### Non-goals

- Building a data lake or a service that runs continuously.
- Teaching the MCP server a vault's taxonomy, file names, states, or proposal
  format.
- Using `.gitignore` to hide review files that should stay tracked.
- Treating search exclusion as access control or secret protection.
- Several indexes or retrieval profiles in the first version.
- Promoting every source, journal entry, or Hindsight recollection
  automatically.
- Requiring approval for the owner's own edits in Obsidian.
- Protecting the vault from an agent with unrestricted shell or filesystem
  access.

### Invariants

- **Ownership.** Agents can suggest changes. Only the owner authorizes an
  agent-initiated publication. A note's own status or content cannot
  authorize it.
- **Source integrity.** A proposal cites what was actually reviewed. A URL
  alone does not show that anyone checked the content.
- **Separate properties.** A note's maturity, certainty, search visibility,
  and approval state are different properties.
- **MCP neutrality.** The MCP server interprets paths, patterns, documents,
  links, and indexes. The template interprets knowledge and approval.
- **Compatibility.** A vault with no ignore file keeps today's MCP behavior.

## 4. Storage

### Proposal storage: proposal files

Each proposal is a Markdown file with YAML frontmatter in a proposals folder.
The owner reviews it in an editor, and in Obsidian once the folder is visible.
A publisher applies the approved revision to the target note.

The alternative was a Git branch per proposal, which the owner reviews as a
diff and merges. Both meet the goals. Proposal files won for four reasons:

- The librarian agents that draft changes, such as `source-distiller` and
  `daily-reviewer`, have MCP and file tools but no shell. They can write a
  proposal file with `obsidian_create_note` today. Branches would require
  giving them Git and a shell, which widens what they can change.
- Obsidian and the MCP server both work on one checkout. A proposal branch
  would either switch the files the owner has open in Obsidian or live in a
  separate worktree the MCP server cannot see.
- A vault repository can hold several vaults, so a proposal branch would
  branch all of them.
- In Phase 2, the owner can review proposals in Obsidian and work through
  several at once. Branches need a checkout switch for each one.

Branches need less new code, but most of the code they save belongs to the
Phase 3 publisher, which may never be needed. Their enforcement advantage is
also smaller than it looks, as the table shows.

| Need | Proposal files | Git branches |
|---|---|---|
| Base drift | Each edit's replaced text must occur once in the target | Merge conflict |
| Revisions | `revision` field, plus a digest per revision in phase 3 | Commits on the branch |
| Approval bound to exact content | Digest the publisher checks | The owner merges a specific commit |
| Closed and rejected proposals | Terminal states, files stay in place | Merged or deleted branches |
| Enforced mode | Separate publisher identity | Branch protection and a merge identity the agent cannot use. An agent with the owner's GitHub login can merge or change the rule. |
| Review in Obsidian | Yes | No, Obsidian shows one checkout |
| Many small proposals at once | Easy | Branch switching is clumsy |
| New code to write | Schema, publisher, validators | Little: Git does most of it |

Git still keeps the history. Proposal files are committed, so
`git log -- .proposals/` shows every revision of every proposal.

### Layout

The layout is this template's choice, not something the MCP server
prescribes. Phase 1 uses hidden folders, which the MCP server always skips:

```text
vaults/<vault-name>/
├── .sources/                  # captured sources (phase 1)
│   └── S-<id>.md
├── .proposals/                # open and closed proposals (phase 1)
│   └── P-<id>.md
├── .archive/agent-memory/     # existing, from PR #14
├── JRNL/YYYY/MM/YYYY-MM-DD.md # existing owner journals, also sources
├── _SYS/
│   ├── REVIEW.base            # review queue (phase 2)
│   └── log.md                 # existing operations log
├── LIFE/  TECH/  WORK/        # curated notes
└── 00.00.md
```

Obsidian hides dot-folders, so in phase 1 the owner lists the queue with
`node scripts/proposal-queue.mjs list` and reads proposals in an editor or
with `git diff`. In phase 2 the folders move to visible `_SOURCES/` and
`_PROPOSALS/`, the ignore file keeps them out of search, and
`_SYS/REVIEW.base` shows open proposals in Obsidian. Neither is a
Johnny Decimal system, and neither uses ACID IDs.

### Source records

A source record holds the passages a proposal relies on, with an ID, the kind
of source, its URL if it has one, and the capture date. A claim can cite only
an excerpt stored in a record, so the record shows exactly what was reviewed,
even after the page behind the URL changes. Git versions the record, which
replaces the checksum earlier drafts carried: the phase 3 publisher detects a
changed source by hashing the record file. Screen for private or sensitive
content before the source enters Git.

```yaml
---
record_type: knowledge-source
source_id: S-20261022-8F3D
source_kind: article
source_url: 'https://example.org/article'
captured_at: '2026-10-22'
---
```

The body holds the excerpts as quotations and notes on where they appear.
Agents do not create a proposal for every source. Journals and existing notes
stay where they are, and a proposal cites them by path.

### Proposal records

One proposal changes one target note. It has a stable ID, the target, the
cited sources, and the change: the complete note for a create, or exact-text
replacements for an update. The
[proposal queue doctrine](../../references/librarian/proposal-queue.md)
defines the body. The template's librarian, checker, and publisher read this
metadata. The MCP server does not.

```yaml
---
record_type: knowledge-proposal
proposal_id: P-20261022-A91B
state: pending
revision: 1
operation: update
target_path: TECH/20-Architecture/21-Patterns/TECH.21.04.md
source_ids: [S-20261022-8F3D]
created_at: '2026-10-22'
updated_at: '2026-10-22'
---
```

The body holds the proposed change, its justification, the claims each source
supports, conflicts with existing notes, a sensitivity check, affected links,
the planned `_SYS/log.md` entry, open questions, and a log of review
decisions.

Phase 1 stores no hash of the target. The agents that write proposals have no
shell, and the MCP server returns no content hash, so they cannot compute one.
Instead, each replacement names the exact text it replaces, and that text must
occur exactly once in the target. An edit to that part of the note fails the
check, and the proposal needs a new revision. Edits elsewhere in the note do
not block it, the same tolerance a patch has.

In phase 3 the publisher computes a digest over the target path, operation,
change, and the hashes of the target and the cited source records. Any edit to
an approved proposal invalidates the approval. A `state: approved` field is a
display value, not a security token.

### Curated notes

Curated notes keep the `SYS.AC.ID` convention, atomic claim titles, links,
navigation headers, `entities`, `communities`, and maturity status. Add
provenance where it helps, without a new required schema for every note. The
owner keeps creating and editing notes directly.

## 5. Ignore file in the MCP server

`obsidian-vault-mcp` v2.2.0 implements
[#25](https://github.com/jabez007/obsidian-vault-mcp/issues/25) and part of
[#26](https://github.com/jabez007/obsidian-vault-mcp/issues/26). Its
[README](https://github.com/jabez007/obsidian-vault-mcp/blob/v2.2.0/README.md)
is the reference. The parts this design relies on:

- `.obsidian-mcpignore` at the vault root selects what discovery and indexing
  see. It does not control Git tracking or access to a path the caller names.
- Rules use the `ignore` library's gitignore matching, case-sensitive on every
  platform. A leading `!` is an error. Write `\!` for a literal `!`.
- The file only narrows the built-in rule. Hidden paths and files without a
  lowercase `.md` suffix stay excluded.
- Explicit reads and edits of an ignored note keep working and never index
  it. An ignored note still counts as an existing wikilink target.
- Note tools refuse to create, edit, or move the ignore file, under any
  casing or symlink alias.
- An unreadable file or invalid line makes indexing and discovery fail with
  the file and line in the error. Index rows stay as they were. Explicit note
  edits still save, with a warning that indexing failed.
- `index-metadata.json` records a fingerprint of the rules. After a rule
  change, `obsidian_rag_query` and `obsidian_prepare_index_snapshot` return
  an error until a whole-vault scan reconciles the index.
- Snapshot manifests record the rules fingerprint, and `sourceFingerprint`
  includes it. Preparation checks every exported row against the rules. When
  a Git hook passes in the staged ignore file, preparation fails if it differs
  from the file on disk.

Still open in the MCP server: refusing to install a snapshot built under
different rules. That belongs to the snapshot adoption work in
[#24](https://github.com/jabez007/obsidian-vault-mcp/issues/24).

The sample ignore file this template would ship lists only the lifecycle
folders:

```gitignore
# Captured sources and pending proposals
/_SOURCES/
/_PROPOSALS/
```

Other candidates, such as `/JRNL/` and `/_SYS/`, change what everyday queries
return. They stay out of the sample until open decision 4 is settled.

**Why not `.gitignore`?** The two files answer different questions: should
Git track this file, and should default search return it? Proposals need to be
tracked but not searched.

## 6. Retrieval

The MCP server's normal search tools cover the files its rules allow. They do
not need a `scope` parameter or a lifecycle column. With sources and proposals
excluded, the librarian's ordinary searches return curated notes and
journals.

Excluded files never enter the index, so the server never filters a mixed
top-K list after the fact, and ranking stays as good as it is today.

A proposal lists its source IDs, so a reviewer or the librarian reads each
source by path. `obsidian_list_notes` and `obsidian_search_notes` never return
hidden or ignored files, so an empty result from them says nothing about the
queue. The doctrine defines how an agent finds queued proposals:

- An agent with a glob or directory listing tool lists
  `vaults/<vault>/.proposals/` by that explicit path.
- An agent without one reads a proposal by the ID the owner gives, with
  `obsidian_read_note` and the path `.proposals/<ID>.md`.
- Some listing tools skip hidden folders, so an empty listing does not prove
  the queue is empty. The agent says so and asks the owner to run
  `node scripts/proposal-queue.mjs list`, which reads the folder directly.

In phase 2 the same rules apply to `_PROPOSALS/`, and the owner can also use
`_SYS/REVIEW.base` in Obsidian. Explicit reads do not index anything. The
first version does not offer full-text or semantic search across excluded
sources and proposals. If that turns out to be needed, it should be a generic
MCP feature, such as named index profiles, with nothing lifecycle-specific in
its API.

A search result names a note's location, excerpts, links, and metadata. It
never says a note is approved or verified. The agent and the vault's own
instructions decide what a result means, and finding a claim in a curated
note does not prove it true.

## 7. Lifecycle, approval, and publication

```text
Capture a source (optional)
  └── Discover related curated notes
        └── Draft a proposal
              ├── revision requested → revised, pending again
              ├── rejected, deferred, or superseded
              └── owner approves an exact revision
                    └── publish checks
                          ├── applied to a curated note
                          └── blocked until corrected or reviewed again
```

Each proposal survives a restart. Closing a proposal sets a terminal state,
`applied`, `rejected`, or `superseded`, and leaves the file and its evidence
in place. An applied proposal names the note it changed in `target_path`, and
records are never deleted.

### Two levels

**Workflow only.** The librarian asks the owner for specific approval in the
conversation and records the proposal. This is a procedure, not a security
boundary, while the agent still has write tools or shell access. Phase 1
implements this level.

**Enforced publication.** A separate publisher that the owner controls applies
an exact proposal revision. The proposing agent cannot forge or edit the
approval. The publisher is a template component that checks the vault,
target, base and source hashes, the payload digest, ID collisions, note
structure, links, sensitivity, and the reviewed diff. It publishes
idempotently, updates the audit state and `_SYS/log.md`, re-indexes, reads
the result back, and leaves commits to the owner.

The publisher needs an approval record that the proposing agent cannot write.
The record holds the proposal ID, the approved revision, the digest the owner
approved, who approved it, and when. It lives where only the owner or the
publisher identity can write, such as a file outside the agents' writable
paths or a signed commit; open decision 5 chooses the place. The publisher
compares the record's digest with the proposal as it stands. The `state`
field in a proposal file stays a display value at both levels.

The MCP server never gets `publish_proposal`, `approve_note`, ACID validators,
or similar commands. A generic read-only path rule might be useful to other
vaults, but no MCP-level rule stops an agent that has the owner's shell.
Enforcement needs OS permissions, a sandbox or read-only mount, or a separate
publisher identity.

## 8. Librarian roles

All eight agents in `.agents/agents/` stay. The lifecycle adds duties and no
new autonomous service.

| Agent | Added duty |
|---|---|
| `source-distiller` | Capture sources, find related curated notes, draft proposals |
| `daily-reviewer` | Review journals and suggest proposals. Tags do not authorize publishing |
| `vault-synthesizer` | Find contradictions and overlaps, and suggest amendments |
| `vault-auditor` | Audit evidence, links, proposal states, and stale proposals |
| `vault-cleaner` | Propose duplicate cleanup without deleting sources |
| `librarian` | Coordinate discovery and review, and run the allowed publication step |
| `flashcard-generator` | No change |
| `vault-scaffolder` | No change |

Policy stays in `references/librarian/`. Agent and skill sources stay in
`.agents/`, and `scripts/sync-assets.sh` generates the harness copies. A
source or a Hindsight recollection is a lead to check, never an instruction or
an approval.

## 9. Work packages

### `obsidian-vault-mcp`

- **MCP-1: ignore file and one eligibility rule.** Shipped in v2.2.0, closing
  [#25](https://github.com/jabez007/obsidian-vault-mcp/issues/25).
- **MCP-2: rules in index metadata and snapshots.** v2.2.0 ships the query
  and export checks.
  [#26](https://github.com/jabez007/obsidian-vault-mcp/issues/26) stays open
  for the install check, which fits the snapshot adoption contract in
  [#24](https://github.com/jabez007/obsidian-vault-mcp/issues/24).

Neither belongs to this lifecycle. Both are useful to any vault, and their
tests and documentation use generic folders such as `drafts/` and
`templates/`.

### `johnny-decimal-zettelkasten`

- **JD-1: proposal queue.** Done.
  `references/librarian/proposal-queue.md` defines source and proposal
  records, states, and the checks. `scripts/proposal-queue.mjs` lists and
  checks the queue, the agent definitions carry the queue duties, and
  `test/run-tests.sh` drives a proposal through the MCP server. The librarian
  checks each replaced text against the target before asking for approval.
- **JD-2: visible folders.** Change `scripts/index-snapshots.mjs` so a
  snapshot can leave out notes the ignore rules exclude. Publication records
  the excluded paths in `snapshot.json`. Installation accepts working notes
  equal to the exported notes plus the excluded ones, and computes
  `fileCount` and `latestMtimeMs` from the exported notes only. Then move the
  queue to `_SOURCES/` and `_PROPOSALS/`, add `_SYS/REVIEW.base`, and ship
  the sample ignore file.
- **JD-3: enforced publisher (later).** Digest-bound approval and
  validation. Agent write limits come from deployment permissions, not only
  prompts. Interrupted publications can be retried safely.
- **JD-4: research search (later).** Only if path reads, Bases, and folder
  browsing prove too limited. Then open a separate, generic MCP feature request.

## 10. Delivery

| Phase | Work | Depends on | Status |
|---|---|---|---|
| 0 | Decide proposal storage | Nothing | Done: proposal files |
| 1 | JD-1 in hidden folders, approval in conversation only | Phase 0 | Done |
| 1 | MCP-1 and MCP-2 | Nothing, runs in parallel | v2.2.0, except the install check |
| 2 | JD-2: snapshot change, visible folders, and sample ignore file | Phase 1 | Not started |
| 3 | JD-3: enforced publisher, then bypass attempts through other tools and the shell | Phase 2 | Later |
| 4 | Duplicate detection, batch review, stale-proposal reminders, JD-4 | Real use showing a need | Later |

Each phase is useful alone. No phase migrates existing notes in bulk.

## 11. Acceptance criteria

### MCP-1 and MCP-2

The issues hold the detailed criteria. v2.2.0 meets all seven, except the
install half of criterion 5.

1. A vault with no ignore file behaves as it does in v2.1.0, after one
   whole-vault scan to upgrade the index metadata.
2. A rule such as `/drafts/` keeps those notes out of RAG, keyword search,
   lists, and backlinks, with no frontmatter convention.
3. Two vaults with different rules do not affect each other.
4. Creating, editing, moving, and reindexing one file never adds an ignored
   path to the index.
5. After a rule change, queries cannot return newly ignored notes, and
   snapshots built under other rules are refused.
6. Note-editing tools cannot write the ignore file.
7. No MCP source file mentions Johnny Decimal, sources, proposals,
   `SYS.AC.ID`, or `knowledge-proposal`.

### Phase 1: proposal queue

8. Sources and proposals can be created, kept across sessions, listed with
   `node scripts/proposal-queue.mjs list` or an agent's listing tool, and
   reviewed, and they never appear in default RAG or keyword results.
9. An agent can research curated notes, cite exact sources, and propose a
   precise change without publishing it.
10. A change to an approved proposal makes the owner approve it again.
11. Documentation and agent instructions call this mode workflow-only and do
    not claim it enforces anything.
12. The owner's direct edits in Obsidian need no approval, and Hindsight stays
    independent.

### Phase 2: visible folders

13. The pre-commit hook publishes a snapshot for a vault whose rules exclude
    notes, and another machine installs it with those notes in its working
    tree.
14. The queue moves to visible folders, the sample ignore file keeps them out
    of default search, and the shared snapshot after the move has no rows for
    them.
15. The documentation says that ignore rules do not remove content from
    earlier Git or Git LFS history.

### Phase 3: enforced publication

16. Stale targets, ID collisions, changed source records, and forbidden
    paths block publication.
17. An agent cannot get around the publisher through other write tools or the
    shell in the supported deployment.

## 12. Decisions

### Recorded

- Lifecycle meaning stays out of the MCP server.
- A separate ignore file, not `.gitignore`, because proposals must be tracked
  but not searched.
- The ignore file selects what is indexed and discovered. It is not an access
  control list.
- One default index in the first version.
- Publication logic stays in this template.
- The proposal queue starts in hidden folders and does not wait for MCP
  changes.
- Policy and schemas use plain names, not medallion labels.
- Proposals are Markdown files with YAML frontmatter, not Git branches
  (former open decision 1). Section 4 gives the reasons.
- The ignore file uses the `ignore` library's gitignore matching,
  case-sensitive, with no `!` negation (former open decision 2).
- The vault-root `.obsidian-mcpignore` is the only configuration source
  (former open decision 3). The MCP server does not read Obsidian's
  excluded-files setting, `userIgnoreFilters` in `.obsidian/app.json`,
  because `.obsidian/` is often kept per device or out of Git, and that
  setting would also hide proposals from the owner's own Obsidian search.

### Open

Decisions 1 to 3 are recorded above. The remaining numbers stay the same so
earlier references still work.

4. **Journal visibility.** Keep `/JRNL/` in default search, which is today's
   behavior, or exclude it. Excluding it changes the answer to "what do I know
   about X" for anything written only in journals.
5. **Review interface.** Phase 1 lists the queue with an owner-run CLI and
   takes decisions in the conversation. Still open: whether later review
   happens in Obsidian or a CLI, and where the approval record lives so the
   proposing agent cannot write it.
6. **Research search.** Whether path reads and Bases are enough, or a generic
   named-index feature becomes worth building.
7. **Private sources.** Track source excerpts in Git, or keep sensitive
   captures outside the repository, like the private archive from PR #14,
   with stable IDs in the vault.

## 13. References

- [PR #14: Separate the knowledge vault from agent memory](https://github.com/jabez007/johnny-decimal-zettelkasten/pull/14)
- [PR #15: Move the template to obsidian-vault-mcp 2.2.0](https://github.com/jabez007/johnny-decimal-zettelkasten/pull/15)
- [PR #18: Move the template to obsidian-vault-mcp 2.3.0](https://github.com/jabez007/johnny-decimal-zettelkasten/pull/18)
- [Knowledge and memory separation design](knowledge-memory-separation.md)
- [Knowledge promotion policy](../../references/librarian/knowledge-promotion.md)
- [Proposal queue policy](../../references/librarian/proposal-queue.md)
- [Knowledge vault guide](../knowledge-vault-guide.md)
- [Hindsight coexistence](../hindsight-coexistence.md)
- [obsidian-vault-mcp v2.2.0 README](https://github.com/jabez007/obsidian-vault-mcp/blob/v2.2.0/README.md)
- [obsidian-vault-mcp#24: snapshot adoption while sessions run](https://github.com/jabez007/obsidian-vault-mcp/issues/24)
- [obsidian-vault-mcp#25: per-vault ignore file](https://github.com/jabez007/obsidian-vault-mcp/issues/25)
- [obsidian-vault-mcp#26: ignore rules in index metadata and snapshots](https://github.com/jabez007/obsidian-vault-mcp/issues/26)

## Summary

The MCP server is a vault-neutral document and index engine with an optional
ignore file. This template defines sources, proposals, trust, approval, and
publication. The two meet through ordinary Markdown files and paths, not a
shared schema.
