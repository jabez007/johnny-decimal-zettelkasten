# **Second Brain: A Compounding Knowledge System**

Most notes are transient—written and forgotten. This system makes knowledge compound over time. Each note you write becomes part of an interconnected network where insights build upon each other, and every hour of thinking leaves something behind that makes future thinking easier.  
This project manages multiple Obsidian vaults, each combining **Johnny Decimal** for structural organization with **Zettelkasten** for emergent meaning through connections. Vault maintenance is augmented by AI librarian agents, and the vault serves as a **persistent memory engine (AGNT system)** for the Gemini CLI.

## **Core Philosophy**

### **1\. Johnny Decimal (Structure)**

Johnny Decimal provides predictable file location through hierarchical numbering. Every note has an unambiguous home. The structure eliminates the paralysis of infinite filing options and makes retrieval predictable.

* **Systems**: Top-level domains (LIFE, WORK, TECH).  
* **Areas**: Major groupings within a system (1–F).  
* **Categories**: Subdivisions within an area (1–F).

### **2\. Zettelkasten (Connection)**

Zettelkasten creates emergent insight through explicit links between notes. Links carry meaning—they explain *why* connections exist.

* **Atomic**: Each note contains one atomic idea.  
* **Evergreen**: Durable knowledge units designed for long-term value.  
* **Claim-titled**: Titles express complete thoughts (e.g., "Writing forces sharper understanding") rather than labels ("Writing").

### **3\. The Librarian (Automation)**

The hierarchy handles organization; the association handles insight. The **AI Librarian** bridges the gap by auditing link health, suggesting evergreen extractions, and scaffolding new systems.

### **4\. Agent Memory (Evolution)**

The vault is not just for you; it is a "World Model" for your AI agents. 
- **Procedural Memory**: Agents store behavioral rules and preferences in the `AGNT` system.
- **Episodic Memory**: Agents log session state in `JRNL/AGNT/`, allowing them to "resume" work across sessions and computers.

## **Quick Start**

Follow these steps to initialize your first vault and enable Agent Memory:

1. **Install Obsidian**: Download from [obsidian.md](https://obsidian.md/).
2. **Install Gemini CLI**: Follow the [official installation guide](https://github.com/google/gemini-cli).
3. **Setup Environment**: 
   ```bash
   cd johnny-decimal-zettelkasten
   ./.gemini/setup-environment.sh
   ```
   *The setup script installs the `gemini-obsidian` extension and configures a **Global Hook** that enables Agent Memory in all your CLI sessions.*
4. **Initialize Vault in Obsidian**: 
   * Open this repository folder as a vault in Obsidian.  
   * Enable **Bases** and **Backlinks** core plugins.
5. **Configure Root Index**: Create `00.00.md` in the root and add the following:  
   >\# Vault Index
   >
   >\!\[\[JDEX\_00.00.base\]\]

6. **Configure your first Base**:  
   * Right-click `_SYS/` → **New base** → Name it `JDEX_00.00`.  
   * Open the file, click the **Filter** icon, and add: `Property: file.name | Operator: ends with | Value: .00.00`.  
   * Set the view to **Cards**.

## **The AGNT System (Agent Memory)**

The `AGNT` system is a dedicated Johnny-Decimal system (Prefix: `AGNT`) that separates machine telemetry from human knowledge.

- **`AGNT/10-Procedural_Rules/`**: Stores atomic, declarative rules (e.g., `AGNT.11.01-Pytest-Preference.md`).
- **`JRNL/AGNT/`**: Stores chronological session logs (`YYYY-MM-DD-HHMM.md`).

### **The Boot/Shutdown Protocol**
The global Gemini CLI is now configured to follow a strict protocol within this vault:
- **Boot**: Automatically restores state by reading the last session log and querying procedural rules via `obsidian_rag_query`.
- **Shutdown**: Logs the session, crystallizes new rules, and appends a **Staff Report** to your current daily note using `obsidian_insert_at_heading`.

## **AI-Assisted Vault Maintenance**

The **Librarian** system uses Gemini CLI subagents to assist with organization and knowledge development. These agents follow a **Proposal-First** mandate: they analyze and suggest actions but **never modify files without explicit approval.**

### **Core Skill: `librarian-vault-manager`**
This is the foundational skill that provides the Johnny-Decimal and Zettelkasten "Constitution" to all agents. It ensures that every action respects ACID notation, atomicity, and structural integrity.

### **Specialized Subagents**
For complex tasks, the Librarian delegates to specialized experts. You can invoke them directly using the `@` syntax in Gemini CLI:

| Agent | Purpose | Key Commands |
| :--- | :--- | :--- |
| **@librarian** | General coordination and ID lookups. | *"Where should I put this note?"*, *"Find ID for X"* |
| **@vault-auditor** | Link health and graph connections. | *"Audit links in the example vault"*, *"Find orphans"* |
| **@vault-cleaner** | Hygiene, duplicates, and renames. | *"Clean up my inbox"*, *"Check for duplicate notes"* |
| **@vault-scaffolder** | Building new JD systems/areas. | *"Create a new WORK system"*, *"Scaffold Area 20"* |
| **@daily-reviewer** | Journal-to-Evergreen crystallization. | *"Review my daily notes from this week"* |
| **@vault-synthesizer** | Knowledge compounding & bridge notes. | *"Synthesize my notes on Topic X"*, *"Any contradictions?"* |
| **@source-distiller** | Processing articles/transcripts. | *"Process this article into atomic notes"* |
| **@flashcard-generator** | Spaced-repetition card creation. | *"Generate flashcards for this note"* |

### **The Crystallization Principle**
Following the **"LLM Wiki"** philosophy, the `@librarian` proactively identifies valuable insights during your CLI sessions and suggests "filing them back" into your vault. This ensures that transient chat context becomes durable, searchable knowledge.

## **System Architecture**

### **ACID Notation**

Every evergreen note uses Area, Category, and ID (ACID) notation with a system prefix: SYS.AC.ID.

| Component | Description | Range |
| :---- | :---- | :---- |
| SYS | System code | 2-4 letters (e.g., LIFE) |
| A | Area | 1-F (Hexadecimal) |
| C | Category | 1-F (Hexadecimal) |
| ID | Unique ID | 01-FF (Hexadecimal) |

**Example:** `LIFE.3A.07` (LIFE system, Area 3, Category A, ID 07).

### **Deviations From Canonical Johnny Decimal**

* **Hexadecimal**: We use 0-F (16 slots) instead of 0-9 (10 slots) to maximize density.  
* **System Prefixes**: Allows multiple separate JD systems within one vault.  
* **Automated Indexes**: Using the **Bases** plugin to replace manual index maintenance.

### **Standard Zeros**

* The `00` area is reserved for system meta-information (indexes).  
* `SYS.00.00` denotes the index file for a system.  
* `00.00` in the vault root is the master index.

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

| Element | Pattern | Example |
| :---- | :---- | :---- |
| System folder | SYS/ | LIFE/ |
| Area folder | A0-Area Name/ | 10-Philosophy/ |
| Category folder | AC-Category Name/ | 11-Productivity/ |
| Note file | SYS.AC.ID-Title.md | LIFE.11.01-Title.md |

### **System Index Template**

The system index file (`SYS.00.00.md`) acts as the entry point for a specific system. It links back to the master index and embeds the relevant Base file:  
>\[\[00.00\]\]
>
>\# LIFE System Index
>
>Description of this system's purpose.
>
>\#\# Quick Navigation
>
>\!\[\[JDEX\_LIFE.base\]\]

### **Note Template**

Every evergreen note begins with a link to its system index to ground it in the hierarchy:  
>\[\[LIFE/00-IDX/LIFE.00.00\]\]
>
>\# Descriptive Claim Title
>
>Content expressing a single atomic concept.

## **Workflow**

1. **Daily Capture**: Record raw thoughts in `JRNL/YYYY/MM/YYYY-MM-DD.md`.
2. **Review & Extract**: Run `@daily-reviewer`. When an idea matures, extract it to an evergreen note using the transclusion/embed method (`![[links]]`) to maintain context without duplication.
3. **Compound & Synthesize**: Use `@vault-synthesizer` to find tensions between notes and create "Bridge Notes" that explore emergent themes.
4. **Audit & Maintain**: Regularly run `@vault-auditor` and `@vault-cleaner` to keep the "knowledge garden" healthy.

## **Advanced Deployment & Integration**

### **Gemini CLI Setup**

1. Install [Gemini CLI](https://github.com/google/gemini-cli).
2. Run the project setup script: `./.gemini/setup-environment.sh`.
3. The specialized subagents in `.gemini/agents/` will be automatically discovered.

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
2. Install the **Obsidian\_to\_Anki** community plugin.

## **External Resources**

* [Johnny Decimal Official Guide](https://johnnydecimal.com/)  
* [Zettelkasten Method Overview](https://zettelkasten.de/overview/)  
* [Andy Matuschak’s Evergreen Notes](https://notes.andymatuschak.org/z5E5QawiXCMbtNtupvxeoEX)
