# **Second Brain: A Compounding Knowledge System**

Most notes are transient—written and forgotten. This system makes knowledge compound over time. Each note you write becomes part of an interconnected network where insights build upon each other, and every hour of thinking leaves something behind that makes future thinking easier.  
This project manages multiple Obsidian vaults, each combining **Johnny Decimal** for structural organization with **Zettelkasten** for emergent meaning through connections. AI librarian agents in four agent CLIs (**Claude Code**, **Codex CLI**, **Gemini CLI**, and **OpenCode**) can search the vault, cite it, and propose additions that you approve. All four share the same Obsidian MCP backend, [`jabez007/obsidian-vault-mcp`](https://github.com/jabez007/obsidian-vault-mcp) v2, published to npm as `@jabez007/obsidian-vault-mcp`. Each harness's setup script installs that backend in its own host while repo-specific agent behavior stays in this template.

> **Upgrading from an earlier version of this template?** Agents no longer keep their memory in the vault, and the session hooks and compiler are gone. The backend was renamed from `gemini-obsidian` to `obsidian-vault-mcp` in v2, which needs a one-time RAG index rebuild. See **[MIGRATION.md](MIGRATION.md)** for both. Pulling the update does not change your notes.

Guides:

- [Use the knowledge vault](docs/knowledge-vault-guide.md): daily use, promotion, and using the vault from other projects.
- [Run Hindsight alongside the vault](docs/hindsight-coexistence.md): optional agent memory, kept separate from the vault.
- [Separating the knowledge vault from agent memory](docs/design/knowledge-memory-separation.md): the design note behind the split.

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

### **4\. Knowledge, Not Agent Memory**

The vault holds what you decided to keep. Agents read it as a reference and add to it only through a proposal you approve. What an agent remembers about past sessions belongs to the agent CLI or to an optional memory provider configured outside this repository, never to the vault.

## **Quick Start**

Follow these steps to initialize your first vault:

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
   The shared setup uses the published npm package,
   `npx -y @jabez007/obsidian-vault-mcp@2.3.0`.
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

## Sharing the search index

Setup installs a pre-commit hook that uses MCP 2.3.0 to publish a validated
LanceDB snapshot for each registered vault after incremental indexing. Database files use Git LFS;
matching metadata and stable vault IDs use ordinary Git. Live databases and
export history stay local.

After setup in each clone, use normal commits and pushes. On the receiving
machine, pull **before starting the MCP**. Git hooks download missing LFS
payloads and install the shared snapshot automatically. Branch switches and
completed rebases also install their matching snapshots. The receiving
machine can search without rebuilding document embeddings.
`git commit -a` works for tracked notes; stage new notes first. Shared text uses
LF line endings so note hashes match across machines, including Git
configurations that default to CRLF.
See [index snapshot setup](docs/index-snapshots.md) for registration, migration
of existing tracked databases and CRLF checkouts, hook compatibility, and commit
policies.

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

`.claude/agents/` · `.claude/skills/` · `.gemini/agents/` · `.opencode/agents/` · `.codex/agents/`

```bash
./scripts/sync-assets.sh   # regenerate after editing any canonical file
```

CI reruns the generator and fails the build if generated files drift, so the copies cannot silently diverge.

Agent bodies reference MCP tools through a `{{MCP_PREFIX}}` placeholder, since each harness namespaces MCP tools differently — `mcp__plugin_obsidian-vault-mcp_obsidian-vault-mcp__` for Claude Code, `mcp_obsidian-vault-mcp_` for Gemini, `obsidian-vault-mcp_` for OpenCode, and bare names for Codex.

### **Specialized Subagents**

For complex tasks, the Librarian delegates to specialized experts. All eight exist in every harness, backed by the same MCP tools.

| Agent                    | Purpose                               | Key Commands                                                |
| :----------------------- | :------------------------------------ | :---------------------------------------------------------- |
| **@librarian**           | General coordination and ID lookups.  | _"Where should I put this note?"_, _"Find ID for X"_        |
| **@vault-auditor**       | Link health and graph connections.    | _"Audit links in the example vault"_, _"Find orphans"_      |
| **@vault-cleaner**       | Hygiene, duplicates, and renames.     | _"Clean up my inbox"_, _"Check for duplicate notes"_        |
| **@vault-scaffolder**    | Building new JD systems/areas.        | _"Create a new WORK system"_, _"Scaffold Area 20"_          |
| **@daily-reviewer**      | Proposes notes from daily notes.      | _"Review my daily notes from this week"_                    |
| **@vault-synthesizer**   | Knowledge compounding & bridge notes. | _"Synthesize my notes on Topic X"_, _"Any contradictions?"_ |
| **@source-distiller**    | Processing articles/transcripts.      | _"Process this article into atomic notes"_                  |
| **@flashcard-generator** | Spaced-repetition card creation.      | _"Generate flashcards for this note"_                       |

### **Knowledge Promotion**

When a CLI session produces something worth keeping, the agent offers to file it. It follows the [promotion workflow](references/librarian/knowledge-promotion.md): it searches for existing notes, proposes a note with labeled claims, sources, and a check for secrets, and writes only after you approve. Nothing from a session reaches the vault any other way.

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
> entities: [<entity-1>, <entity-2>, <entity-3>]
> communities: [<jd-category-or-cluster>]
> status: distilled
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
3. **Promote**: At the end of a working session, ask the agent to promote what it learned. Review the proposal before it is written.
4. **Compound & Synthesize**: Use `@vault-synthesizer` to find tensions between notes and create "Bridge Notes" that explore emergent themes.
5. **Audit & Maintain**: Regularly run `@vault-auditor` and `@vault-cleaner` to keep the "knowledge garden" healthy.

## **Advanced Deployment & Integration**

### **AI CLI Setup**

Every harness reads the same vault config (`~/.obsidian-mcp.config.json`) and the same MCP backend, so you can mix and match freely.

| Harness | Setup | Reads |
| :--- | :--- | :--- |
| **Claude Code** | `./.claude/setup-environment.sh` | `CLAUDE.md` (which imports `AGENTS.md`), `.claude/agents/`, `.claude/skills/` |
| **Codex CLI** | `./.codex/setup-environment.sh` | `AGENTS.md`, `.codex/agents/`, `.agents/skills/` |
| **Gemini CLI** | `./.gemini/setup-environment.sh` | `AGENTS.md` (through `.gemini/settings.json`), `.gemini/agents/`, `.agents/skills/` |
| **OpenCode** | `./.opencode/setup-environment.sh` | `AGENTS.md`, `.opencode/agents/`, `.agents/skills/`, `opencode.json` |

Notes:

- **Claude Code** and **Codex** install the backend as a plugin from the upstream marketplace. **Gemini** installs it as an extension. **OpenCode** launches it directly from `opencode.json`.
- The Gemini setup removes the global `agent-memory-boot` hook that earlier versions of this template installed.
- Codex reads `.codex/agents/` only in a project you have trusted. Its custom agents inherit every MCP tool, so an agent's tool list is enforced in Claude Code, Gemini, and OpenCode but is only an instruction in Codex.

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
