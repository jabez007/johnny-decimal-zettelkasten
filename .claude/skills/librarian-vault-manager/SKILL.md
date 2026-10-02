---
name: librarian-vault-manager
description: Knowledge steward for Johnny-Decimal/Zettelkasten Obsidian vaults. Use when managing vault structure, auditing links, cleaning up notes, constructing new vault sections, reviewing daily notes, generating flashcards, or performing active knowledge synthesis. Responds to keywords like "organize my vault", "check my index", "review daily notes", "audit links", "cleanup notes", "create new vault section", "generate flashcards", "Johnny Decimal", "Zettelkasten", "process source", "refactor note", "synthesize vault", "vault health check".
---

<!-- GENERATED FILE — DO NOT EDIT.
     Source: .agents/skills/librarian-vault-manager/SKILL.md
     Regenerate with: ./scripts/sync-assets.sh -->

# **Librarian Vault Manager**

## **Overview**

This skill provides the foundational knowledge and rules for managing Obsidian vaults structured using the Johnny-Decimal and Zettelkasten methodologies, enhanced with graph-aware metadata for advanced RAG systems.

## Scope

Use this management skill only from the repository that owns the selected vault.
Check `obsidian_get_config` and the current Git worktree root before managing
notes. From other projects, research across systems and capture candidates in
`JRNL/`; leave crystallization and permanent-note changes for local review.

## **Core Mandates**

- **Graph-Aware Metadata:** **CRITICAL.** Every permanent note MUST include YAML frontmatter with required core fields `entities`, `communities`, and `status`. Add `aliases` and `tags` when they improve discoverability or actionable intent.
- **Proposal-first management:** Propose placement, IDs, and metadata before structural or bulk note changes. Existing user authorization remains valid; do not ask again for approved work. Journal capture follows the global capture workflow.
- **Respect ACID Notation:** All references must strictly follow the `SYS.AC.ID` format (Area, Category, ID).
- **Adherence to Vault Guidelines:** Consult `references/librarian/copilot-instructions.md` for identity, atomicity, titles, and links.
- **Maintain JDex Integrity:** `00.00.md` index and `_SYS/*.base` configuration must be kept consistent.

## **System Knowledge**

- **Graph-RAG Hybrid:** A methodology where structured frontmatter (entities, communities) is injected into the text for embedding, enabling "graph-aware" semantic search.
- **Johnny Decimal:** Hierarchical organization (Area -> Category -> ID). `00` is reserved for indices.
- **Zettelkasten:** Atomic, evergreen notes that evolve from transient observations to durable knowledge.
- **Agent Memory (AGNT):** A specialized system for Procedural Memory (Rules in `AGNT/`) and Episodic Memory (Logs in `JRNL/AGNT/`). The `AGNT` system is strictly for agent procedural rules, coding standards, and user preferences. It MUST remain entirely isolated from the user's personal knowledge domains (`LIFE`, `WORK`, etc.). An agent must never store facts about the world in `AGNT`, and must never store rules about how to act in the user's personal domains. Procedural rules use strict JD ACID notation and declarative titles.
- **Journal System (JRNL):** The `JRNL/` system (including `JRNL/AGNT/`) is the transient scratchpad and Episodic Memory. While indexed by the RAG database for historical context and recall, its contents must never be treated as authoritative, crystallized knowledge. Use evergreen notes as the working reference. Newer conflicting journal evidence requires review against the user's current instructions; do not discard it. Scaffolded examples are not adopted preferences.

## **MCP Backend**

Vault reads and writes go through the `obsidian-vault-mcp` MCP server ([`jabez007/obsidian-vault-mcp`](https://github.com/jabez007/obsidian-vault-mcp), v2+). Two behaviors matter when proposing changes:

- `obsidian_create_note` and `obsidian_move_note` refuse to overwrite an existing file unless `overwrite: true` is passed. Treat a refusal as an ACID ID collision to resolve, not an error to force past.
- Note-writing tools re-index the changed note inside the server, so no separate re-index step is needed after a write.

## **Mandatory YAML Schema**

Every permanent note must start with YAML frontmatter whose required core fields are:

```yaml
---
entities: [<entity-1>, <entity-2>, <entity-3>]
communities: [<canonical-community>]
status: distilled
---
```

Allowed values: `distilled`, `crystallized`, `synthesized`, `scaffolded`.

Replace every `<token>` before writing a note. `entities` and `communities` are
exact-match filter keys, so placeholder text becomes an unusable graph label.

`aliases` and `tags` may also be included when they add useful synonyms or actionable intent.


## Community catalogue

Read `_SYS/metadata-catalogue.yaml` with `obsidian_read_note`
before choosing communities or filtering retrieval. Use its canonical labels
in permanent-note proposals and writes. Propose missing labels with definitions
and explicit synonyms; do not infer synonyms from similar spelling or meaning.
If the catalogue is absent or malformed, report it and use verified existing
labels while proposing adoption or repair. Do not invent a replacement catalogue.

Communities group knowledge and may span systems. Folder placement follows ACID
rules independently; the AGNT procedural/domain boundary still applies. Moving
a note does not itself change its communities. Entities remain extensible;
reuse exact existing names and disambiguate unclear names. Note `aliases` name
individual notes and do not define community synonyms.

For community searches, pass the canonical label and all declared synonyms in
one `communities` array. Include case variants verified in existing notes when
reviewing legacy content or journals. The backend matches exact strings and
ORs values within one filter; adding `entities` also constrains the results.
For unknown labels, use an unfiltered query or labels verified in source notes.
Follow a thin filtered result with an unfiltered query. Never pass an invented
label as a filter. Normalization requires a reviewed proposal and local approval;
preserve journal evidence and change only approved permanent-note fields.

Keep the template core labels `Agent Procedural Memory` and `Vault Navigation`
stable. Each vault owns its catalogue and can add approved communities. A new
system does not require a new community. Start with an inventory of existing
labels and source notes when adopting a catalogue; entity registration is optional.

For a normalization proposal, record each note's current and proposed community
arrays and identify unknown labels separately. Re-read the catalogue and notes
before applying approved changes. Use `obsidian_update_frontmatter` to change
only `communities`; it also reindexes the note. Preserve note aliases, tags,
status, entities, body, and source journals. Catalogue creation or edits require
the local proposal workflow. The read-only helper commands and schema are
documented in `docs/metadata-catalogue.md` for repository maintenance.

## **Librarian Specialists (Subagents)**

The parent session coordinates these specialists directly. The librarian returns recommendations and never spawns nested specialists. Use the shared policies below; native tool enforcement differs by harness (see `docs/setup.md`). The daily reviewer returns proposals and cannot apply them:

- `@librarian`: General vault questions, ID lookups, and coordination.
- `@vault-auditor`: Audit link health, identify orphans, and suggest connections.
- `@vault-cleaner`: Maintain hygiene, detect duplicates, and fix naming issues.
- `@vault-synthesizer`: Identify contradictions, synergies, and gaps; propose synthesis notes.
- `@vault-scaffolder`: Create new systems, areas, or categories from scratch.
- `@daily-reviewer`: Extract durable knowledge and recurring themes from daily logs.
- `@source-distiller`: Process long-form content (articles, transcripts) into atomic notes.
- `@flashcard-generator`: Automatically create study materials from notes.

## **General Reference Documents**

- **Johnny Decimal System**: `references/librarian/johnny-decimal.md`
- **Zettelkasten Method**: `references/librarian/zettelkasten.md`
- **Vault Philosophy**: `references/librarian/philosophy.md`
- **Copilot Instructions**: `references/librarian/copilot-instructions.md`
