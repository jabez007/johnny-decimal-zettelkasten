# **Second Brain: A Compounding Knowledge System**

Most notes are transient—written and forgotten. This system makes knowledge compound over time. Each note you write becomes part of an interconnected network where insights build upon each other, and every hour of thinking leaves something behind that makes future thinking easier.  
This project manages multiple Obsidian vaults, each combining **Johnny Decimal** for structural organization with **Zettelkasten** for emergent meaning through connections. Vault maintenance is augmented by AI librarian agents, and the vault serves as a **persistent memory engine (AGNT system)** for four agent CLIs: **Claude Code**, **Codex CLI**, **Gemini CLI**, and **OpenCode**. All four share the same Obsidian MCP backend, [`jabez007/obsidian-vault-mcp`](https://github.com/jabez007/obsidian-vault-mcp) v2, published to npm as `@jabez007/obsidian-vault-mcp`. Each harness's setup script installs that backend in its own host while repo-specific agent behavior stays in this template.

> **Upgrading from an earlier version of this template?** The backend was renamed from `gemini-obsidian` to `obsidian-vault-mcp` in v2, and a one-time RAG index rebuild is required. See **[MIGRATION.md](MIGRATION.md)**. Your vault conventions and note content are unaffected.

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
2. **Install your AI CLI** — any one of:
   - **Claude Code**: [installation guide](https://claude.com/claude-code)
   - **Codex CLI**: [official Codex docs](https://developers.openai.com/codex/cli)
   - **Gemini CLI**: [official installation guide](https://github.com/google/gemini-cli)
   - **OpenCode**: [opencode.ai](https://opencode.ai)
3. **Run the matching setup script**:
   ```bash
   cd johnny-decimal-zettelkasten
   ./.claude/setup-environment.sh      # Claude Code
   ./.codex/setup-environment.sh       # Codex CLI
   ./.gemini/setup-environment.sh      # Gemini CLI
   ./.opencode/setup-environment.sh    # OpenCode
   ```
   Run one per harness you use; they are independent and share the same vault
   config. Each targets a vault inside `vaults/<vault-name>/` (default:
   `vaults/example/`) and persists the selection to `~/.obsidian-mcp.config.json`.
   Because the backend ships on npm, there is no clone-and-build step — every
   host launches it with `npx -y @jabez007/obsidian-vault-mcp@2`.
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

The boot context itself is canonical in `scripts/agent-memory-context.sh`; each harness hook wraps that one script in whatever JSON shape it expects.

| Harness | Boot mechanism |
| :--- | :--- |
| **Claude Code** | `SessionStart` hook in `.claude/settings.json` → `.claude/hooks/session-start.sh` |
| **Codex CLI** | `SessionStart` hook in `.codex/config.toml` → `.codex/hooks/session-start.sh` |
| **Gemini CLI** | Global `SessionStart` hook installed by the setup script into `~/.gemini/hooks/` |
| **OpenCode** | No command-based session hook; `AGENTS.md` carries the standing rules |

- **Shared workflow**: every harness should restore context from recent `JRNL/AGNT/` logs, query existing procedural rules before acting, and write new durable rules back into `AGNT/` when appropriate.

## **AI-Assisted Vault Maintenance**

The **Librarian** system works identically across all four harnesses. Every agent follows the same doctrine in `references/librarian/`, and the operating stance is always **Proposal-First** for structural work: analyze first, then make deliberate vault changes with clear rationale.

### **Single Source of Truth**

Agent policies and doctrine are written **once** and generated into each harness's native format. This is what keeps four harnesses from drifting apart.

**Canonical — edit these:**

| Path | Contents |
| :--- | :--- |
| `references/librarian/*.md` | Johnny-Decimal / Zettelkasten "Constitution" |
| `.agents/skills/librarian-vault-manager/SKILL.md` | Skill body |
| `.agents/agents/*.md` | The eight agent policies |

**Generated — never edit by hand:**

`.claude/agents/` · `.claude/skills/` · `.gemini/agents/` · `.gemini/skills/` · `.opencode/agents/` · `.codex/agents/` · `.codex/config.toml`

```bash
./scripts/sync-assets.sh   # regenerate after editing any canonical file
```

CI reruns the generator and fails the build if generated files drift, so the copies cannot silently diverge.

Agent bodies reference MCP tools through a `{{MCP_PREFIX}}` placeholder, since each harness namespaces MCP tools differently — `mcp__obsidian-vault-mcp__` for Claude Code, `mcp_obsidian-vault-mcp_` for Gemini, `obsidian-vault-mcp_` for OpenCode, and bare names for Codex.

### **Specialized Subagents**

For complex tasks, the Librarian delegates to specialized experts. All eight exist in every harness, backed by the same MCP tools.

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

Every harness reads the same vault config (`~/.obsidian-mcp.config.json`) and the same MCP backend, so you can mix and match freely.

| Harness | Setup | Reads |
| :--- | :--- | :--- |
| **Claude Code** | `./.claude/setup-environment.sh` | `CLAUDE.md`, `.claude/agents/`, `.claude/skills/`, `.claude/settings.json` |
| **Codex CLI** | `./.codex/setup-environment.sh` | `AGENTS.md`, `.codex/agents/`, `.codex/config.toml`, `.agents/skills/` |
| **Gemini CLI** | `./.gemini/setup-environment.sh` | `.gemini/agents/`, `.gemini/skills/`, global `~/.gemini/hooks/` |
| **OpenCode** | `./.opencode/setup-environment.sh` | `AGENTS.md`, `.opencode/agents/`, `opencode.json` |

Notes:

- **Claude Code** and **Codex** install the backend as a plugin from the upstream marketplace. **Gemini** installs it as an extension. **OpenCode** launches it directly from `opencode.json`.
- On the first Codex run, review and trust the repo-local hooks if prompted via `/hooks`.
- OpenCode has no command-based `SessionStart` hook, so the Recent Activity Map is not auto-injected there; `AGENTS.md` carries the standing rules and agents can read `JRNL/AGNT/` on demand.

#### **Cross-CLI Session Compilation**

The session compiler reads logs from all four harnesses in one pass — Gemini (`~/.gemini/tmp`), Codex (`~/.codex/sessions`), Claude Code (`~/.claude/projects`), and OpenCode (SQLite at `~/.local/share/opencode/opencode.db`, which requires `sqlite3` on your PATH).

```bash
# Compile the last 7 days and review with the default host (gemini)
./scripts/compile-sessions.sh 7

# Compile a date range and review with a specific host
AI_MEMORY_HOST=claude ./scripts/compile-sessions.sh 2026-08-01 2026-08-06

# Inspect what would be sent, without invoking a model
AI_MEMORY_DRY_RUN=dump ./scripts/compile-sessions.sh 3
```

`AI_MEMORY_HOST` accepts `gemini` (default), `codex`, `claude`, or `opencode`. The legacy path under `.gemini/skills/librarian-vault-manager/scripts/compile-sessions.sh` remains as a compatibility wrapper.

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
