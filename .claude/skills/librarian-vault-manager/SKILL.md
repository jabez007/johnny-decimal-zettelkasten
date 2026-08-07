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

## **Core Mandates**

- **Graph-Aware Metadata:** **CRITICAL.** Every permanent note MUST include YAML frontmatter with required core fields `entities`, `communities`, and `status`. Add `aliases` and `tags` when they improve discoverability or actionable intent.
- **Read-Only Analysis and Proposals:** **NEVER** create, modify, or delete files directly without a preceding proposal phase.
- **Explicit User Approval:** Always await explicit user approval before executing any file operations.
- **Respect ACID Notation:** All references must strictly follow the `SYS.AC.ID` format (Area, Category, ID).
- **Adherence to Vault Guidelines:** Consult `references/librarian/copilot-instructions.md` for identity, atomicity, titles, and links.
- **Maintain JDex Integrity:** `00.00.md` index and `_SYS/*.base` configuration must be kept consistent.

## **System Knowledge**

- **Graph-RAG Hybrid:** A methodology where structured frontmatter (entities, communities) is injected into the text for embedding, enabling "graph-aware" semantic search.
- **Johnny Decimal:** Hierarchical organization (Area -> Category -> ID). `00` is reserved for indices.
- **Zettelkasten:** Atomic, evergreen notes that evolve from transient observations to durable knowledge.
- **Agent Memory (AGNT):** A specialized system for Procedural Memory (Rules in `AGNT/`) and Episodic Memory (Logs in `JRNL/AGNT/`). The `AGNT` system is strictly for agent procedural rules, coding standards, and user preferences. It MUST remain entirely isolated from the user's personal knowledge domains (`LIFE`, `WORK`, etc.). An agent must never store facts about the world in `AGNT`, and must never store rules about how to act in the user's personal domains. Procedural rules use strict JD ACID notation and declarative titles.
- **Journal System (JRNL):** The `JRNL/` system (including `JRNL/AGNT/`) is the transient scratchpad and Episodic Memory. While indexed by the RAG database for historical context and recall, its contents must never be treated as authoritative, crystallized knowledge. If a RAG query returns a conflict between a `JRNL` note and an evergreen `SYS.AC.ID` note, the evergreen note always takes precedence.

## **MCP Backend**

Vault reads and writes go through the `obsidian-vault-mcp` MCP server ([`jabez007/obsidian-vault-mcp`](https://github.com/jabez007/obsidian-vault-mcp), v2+). Two behaviors matter when proposing changes:

- `obsidian_create_note` and `obsidian_move_note` refuse to overwrite an existing file unless `overwrite: true` is passed. Treat a refusal as an ACID ID collision to resolve, not an error to force past.
- Note-writing tools re-index the changed note inside the server, so no separate re-index step is needed after a write.

## **Mandatory YAML Schema**

Every note must start with YAML frontmatter whose required core fields are:

```yaml
---
entities: [<entity-1>, <entity-2>, <entity-3>]
communities: [<jd-category-or-cluster>]
status: [distilled|crystallized|synthesized|scaffolded]
---
```

Replace every `<token>` before writing a note. `entities` and `communities` are
exact-match filter keys, so placeholder text becomes an unusable graph label.

`aliases` and `tags` may also be included when they add useful synonyms or actionable intent.

## **Librarian Specialists (Subagents)**

For complex workflows, delegate to these specialized subagents:

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
