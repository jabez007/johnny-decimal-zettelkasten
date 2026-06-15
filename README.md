# **Second Brain: A Compounding Knowledge System**

Most notes are transient—written and forgotten. This system makes knowledge compound over time. Each note you write becomes part of an interconnected network where insights build upon each other, and every hour of thinking leaves something behind that makes future thinking easier.  
This project manages multiple Obsidian vaults, each combining **Johnny Decimal** for structural organization with **Zettelkasten** for emergent meaning through connections. Vault maintenance is augmented by AI librarian agents, and the vault serves as a **persistent memory engine (AGNT system)** for both Gemini CLI and Codex CLI. Both CLIs share the same Obsidian MCP backend from the [`jabez007/gemini-obsidian`](https://github.com/jabez007/gemini-obsidian) fork, and each setup script installs that backend globally in its host while keeping repo-specific agent behavior in this template.

## **Core Philosophy**

### **1\. Johnny Decimal (Structure)**

Johnny Decimal provides predictable file location through hierarchical numbering. Every note has an unambiguous home. The structure eliminates the paralysis of infinite filing options and makes retrieval predictable.

- **Systems**: Top-level domains (LIFE, WORK, TECH).
- **Areas**: Major groupings within a system (1–F).
- **Categories**: Subdivisions within an area (1–F).

### **2\. Zettelkasten (Connection)**

Zettelkasten creates emergent insight through explicit links between notes. Links carry meaning—they explain _why_ connections exist.

- **Atomic**: Each note contains one atomic idea.
- **Evergreen**: Durable knowledge units designed for long-term value.
- **Claim-titled**: Titles express complete thoughts (e.g., "Writing forces sharper understanding") rather than labels ("Writing").

### **3\. The Librarian (Automation)**

The hierarchy handles organization; the association handles insight. The **AI Librarian** bridges the gap by auditing link health, suggesting evergreen extractions, and scaffolding new systems.

### **4\. Agent Memory (Evolution)**

The vault is not just for you; it is a "World Model" for your AI agents.

- **Procedural Memory**: Agents store behavioral rules and preferences in the `AGNT` system.
- **Episodic Memory**: Agents log session state in `JRNL/AGNT/`, allowing them to "resume" work across sessions and computers.

## **Quick Start**

Follow these steps to initialize your first vault and enable Agent Memory:

1. **Install Obsidian**: Download from [obsidian.md](https://obsidian.md/).
2. **Install your AI CLI**:
   - **Gemini CLI**: Follow the [official installation guide](https://github.com/google/gemini-cli).
   - **Codex CLI**: Follow the [official Codex docs](https://developers.openai.com/codex/cli).
3. **Run the matching setup script**:
   - **Gemini CLI**
     ```bash
     cd johnny-decimal-zettelkasten
     ./.gemini/setup-environment.sh
     ```
   - **Codex CLI**
     ```bash
     cd johnny-decimal-zettelkasten
     ./.codex/setup-environment.sh
     ```
   Both scripts target a vault inside `vaults/<vault-name>/`. The default is `vaults/example/`.
   Gemini installs the shared backend globally through the Gemini extension system. Codex installs the same backend globally through the Codex plugin system. In both cases, the backend source is [`jabez007/gemini-obsidian`](https://github.com/jabez007/gemini-obsidian), and both scripts persist vault selection through the shared MCP config in `~/.obsidian-mcp.config.json`.
4. **Initialize the actual vault in Obsidian**:
   - Open `vaults/<vault-name>/` as the Obsidian vault, not the repository root.
   - Enable **Bases** and **Backlinks** core plugins.
5. **Configure Root Index**: Create `vaults/<vault-name>/00.00.md` and add the following:

   > \# Vault Index
   >
   > \!\[\[JDEX_00.00.base\]\]

6. **Configure your first Base**:
   - Right-click `vaults/<vault-name>/_SYS/` → **New base** → Name it `JDEX_00.00`.
   - Open the file, click the **Filter** icon, and add: `Property: file.name | Operator: ends with | Value: .00.00`.
   - Set the view to **Cards**.

## **The AGNT System (Agent Memory)**

The `AGNT` system is a dedicated Johnny-Decimal system (Prefix: `AGNT`) that separates machine telemetry from human knowledge.

- **`AGNT/10-Procedural_Rules/`**: Stores atomic, declarative rules (e.g., `AGNT.11.01-Pytest-Preference.md`).
- **`JRNL/AGNT/`**: Stores chronological session logs (`YYYY-MM-DD-HHMM.md`).

### **The Boot/Shutdown Protocol**

- **Gemini CLI**: The setup script installs a global SessionStart hook that restores recent vault state and procedural rules.
- **Codex CLI**: Repository-level `AGENTS.md`, `.codex/agents/`, and the project-local `SessionStart` hook in `.codex/config.toml` provide Codex-native repo behavior. The setup script installs the shared `jabez007/gemini-obsidian` backend globally as a Codex plugin and writes vault selection into `~/.obsidian-mcp.config.json`.
- **Shared workflow**: Both CLIs should restore context from recent `JRNL/AGNT/` logs, query existing procedural rules before acting, and write new durable rules back into `AGNT/` when appropriate.

## **AI-Assisted Vault Maintenance**

The **Librarian** system supports both Gemini CLI and Codex CLI. Gemini uses `.gemini/agents/`; Codex uses root-level `AGENTS.md` and `.codex/agents/`. Both environments use the same `jabez007/gemini-obsidian` MCP backend, but neither setup depends on the other. Shared doctrine lives in `references/librarian/`. The intended role split is the same in both environments: a general librarian plus specialist reviewers, auditors, cleaners, scaffolders, synthesizers, distillers, and flashcard generators. In both environments the operating stance is **Proposal-First** for structural work: analyze first, then make deliberate vault changes with clear rationale.

### **Shared Doctrine**

The foundational Johnny-Decimal and Zettelkasten "Constitution" now lives in `references/librarian/`. Both Gemini and Codex specialist agents should follow that shared doctrine so the two CLIs behave consistently.

### **Specialized Subagents**

For complex tasks, the Librarian delegates to specialized experts. Gemini exposes these through `.gemini/agents/`; Codex exposes matching repository-local agents under `.codex/agents/`, backed by the same MCP tools.

| Agent                    | Purpose                               | Key Commands                                                |
| :----------------------- | :------------------------------------ | :---------------------------------------------------------- |
| **@librarian**           | General coordination and ID lookups.  | _"Where should I put this note?"_, _"Find ID for X"_        |
| **@vault-auditor**       | Link health and graph connections.    | _"Audit links in the example vault"_, _"Find orphans"_      |
| **@vault-cleaner**       | Hygiene, duplicates, and renames.     | _"Clean up my inbox"_, _"Check for duplicate notes"_        |
| **@vault-scaffolder**    | Building new JD systems/areas.        | _"Create a new WORK system"_, _"Scaffold Area 20"_          |
| **@daily-reviewer**      | Journal-to-Evergreen crystallization. | _"Review my daily notes from this week"_                    |
| **@vault-synthesizer**   | Knowledge compounding & bridge notes. | _"Synthesize my notes on Topic X"_, _"Any contradictions?"_ |
| **@source-distiller**    | Processing articles/transcripts.      | _"Process this article into atomic notes"_                  |
| **@flashcard-generator** | Spaced-repetition card creation.      | _"Generate flashcards for this note"_                       |

### **The Crystallization Principle**

Following the **"LLM Wiki"** philosophy, the `@librarian` proactively identifies valuable insights during your CLI sessions and suggests "filing them back" into your vault. This ensures that transient chat context becomes durable, searchable knowledge.

## **System Architecture**

### **ACID Notation**

Every evergreen note uses Area, Category, and ID (ACID) notation with a system prefix: SYS.AC.ID.

| Component | Description | Range                    |
| :-------- | :---------- | :----------------------- |
| SYS       | System code | 2-4 letters (e.g., LIFE) |
| A         | Area        | 1-F (Hexadecimal)        |
| C         | Category    | 1-F (Hexadecimal)        |
| ID        | Unique ID   | 01-FF (Hexadecimal)      |

**Example:** `LIFE.3A.07` (LIFE system, Area 3, Category A, ID 07).

### **Deviations From Canonical Johnny Decimal**

- **Hexadecimal**: We use 0-F (16 slots) instead of 0-9 (10 slots) to maximize density.
- **System Prefixes**: Allows multiple separate JD systems within one vault.
- **Automated Indexes**: Using the **Bases** plugin to replace manual index maintenance.

### **Standard Zeros**

- The `00` area is reserved for system meta-information (indexes).
- `SYS.00.00` denotes the index file for a system.
- `00.00` in the vault root is the master index.

### **Folder Structure**

```
VAULT/
├── _SYS/
│   ├── JDEX_00.00.base
│   ├── JDEX_LIFE.base
│   └── TMPL/
│       └── Daily.md
├── LIFE/
│   ├── 00-IDX/
│   │   └── LIFE.00.00.md        ← System index
│   ├── 10-Area Name/
│   │   └── 11-Category Name/
│   │       └── LIFE.11.01-Title.md
├── JRNL/
│   └── YYYY/MM/YYYY-MM-DD.md    ← Daily notes
└── 00.00.md                     ← Root index
```

### **Naming Conventions**

| Element         | Pattern            | Example             |
| :-------------- | :----------------- | :------------------ |
| System folder   | SYS/               | LIFE/               |
| Area folder     | A0-Area Name/      | 10-Philosophy/      |
| Category folder | AC-Category Name/  | 11-Productivity/    |
| Note file       | SYS.AC.ID-Title.md | LIFE.11.01-Title.md |

### **System Index Template**

The system index file (`SYS.00.00.md`) acts as the entry point for a specific system. It links back to the master index and embeds the relevant Base file:

> \[\[00.00\]\]
>
> \# LIFE System Index
>
> Description of this system's purpose.
>
> \#\# Quick Navigation
>
> \!\[\[JDEX_LIFE.base\]\]

### **Note Template**

Every evergreen note MUST begin with a strict YAML frontmatter block for the graph-aware RAG database, followed by a link to its system index to ground it in the hierarchy:

> ```yaml
> ---
> entities: [3-5 core concepts, people, or technical terms]
> communities: [The broader Johnny-Decimal category or thematic cluster]
> status: [distilled|crystallized|synthesized|scaffolded]
> ---
> ```
>
> \[\[LIFE/00-IDX/LIFE.00.00\]\]
>
> \# Descriptive Claim Title
>
> Content expressing a single atomic concept.

## **Workflow**

1. **Daily Capture**: Record raw thoughts in `JRNL/YYYY/MM/YYYY-MM-DD.md`.
2. **Review & Extract**: Run `@daily-reviewer`. When an idea matures, extract it to an evergreen note using the transclusion/embed method (`![[links]]`) to maintain context without duplication.
3. **Compound & Synthesize**: Use `@vault-synthesizer` to find tensions between notes and create "Bridge Notes" that explore emergent themes.
4. **Audit & Maintain**: Regularly run `@vault-auditor` and `@vault-cleaner` to keep the "knowledge garden" healthy.

## **Advanced Deployment & Integration**

### **AI CLI Setup**

#### **Gemini CLI**

1. Install [Gemini CLI](https://github.com/google/gemini-cli).
2. Run the project setup script: `./.gemini/setup-environment.sh`.
3. The specialized agent policies in `.gemini/agents/` will be automatically discovered.

#### **Codex CLI**

1. Install [Codex CLI](https://developers.openai.com/codex/cli).
2. Run `./.codex/setup-environment.sh`.
3. The script clones and builds the shared `gemini-obsidian` backend under `~/.codex/vendor/gemini-obsidian`.
4. The script installs or updates the global Codex plugin from that backend using Codex's plugin marketplace.
5. On the first project run, review and trust the repo-local hooks if Codex prompts you to do so via `/hooks`.
6. Codex will load repository guidance from `AGENTS.md`, repo-local custom agents from `.codex/agents/`, the project-local `SessionStart` hook from `.codex/config.toml`, and the shared vault config stored in `~/.obsidian-mcp.config.json`.

#### **Cross-CLI Session Compilation**

The session compiler now supports both `~/.gemini` and `~/.codex` session logs:

```bash
# Gemini host (default)
./scripts/compile-sessions.sh

# Codex host
AI_MEMORY_HOST=codex ./scripts/compile-sessions.sh
```

The legacy path under `.gemini/skills/librarian-vault-manager/scripts/compile-sessions.sh` remains as a compatibility wrapper.

### **Dockerized Obsidian**

For a consistent environment, use the provided docker-compose.yml.

1. **Set Permissions**: Run `id -u` and `id -g` and update the `PUID`/`PGID` in docker-compose.yml.
2. **Launch**: `docker compose up -d`.
3. **Access**: Navigate to https://localhost:3001.

### **Web Clipper**

Capture web content directly into your daily notes.

1. Install the **Obsidian Web Clipper** browser extension.
2. **Docker Users**: Run `./setup-obsidian-uri.sh` on your host.

### **Anki Integration**

1. Install **Anki** and the **AnkiConnect** add-on (code: 2055492159).
2. Install the **Obsidian_to_Anki** community plugin.

## **External Resources**

- [Johnny Decimal Official Guide](https://johnnydecimal.com/)
- [Zettelkasten Method Overview](https://zettelkasten.de/overview/)
- [Andy Matuschak’s Evergreen Notes](https://notes.andymatuschak.org/z5E5QawiXCMbtNtupvxeoEX)
