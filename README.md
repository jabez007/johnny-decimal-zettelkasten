# **Second Brain: A Compounding Knowledge System**

Most notes are transient—written and forgotten. This system makes knowledge compound over time. Each note you write becomes part of an interconnected network where insights build upon each other, and every hour of thinking leaves something behind that makes future thinking easier.  
This project manages multiple Obsidian vaults, each combining **Johnny Decimal** for structural organization with **Zettelkasten** for emergent meaning through connections. Vault maintenance is augmented by AI librarian agents.

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

## **Quick Start**

Follow these steps to initialize your first vault:

1. **Install Obsidian**: Download from [obsidian.md](https://obsidian.md/).  
2. **Initialize Vault**: Open this repository folder as a vault in Obsidian.  
3. **Enable Core Plugins**:  
   * Go to Settings → Core Plugins.  
   * Enable **Bases** (for dynamic indexes) and **Backlinks** (for Zettelkasten connections).  
4. **Create System Folders**: Create a \_SYS folder in your vault root to hold configuration files.  
5. **Initialize Root Index**: Create 00.00.md in the root and add the following:  
   >\# Vault Index
   >
   >\!\[\[JDEX\_00.00.base\]\]

6. **Configure your first Base**:  
   * Right-click \_SYS/ → **New base** → Name it JDEX\_00.00.  
   * Open the file, click the **Filter** icon, and add: Property: file.name | Operator: ends with | Value: .00.00.  
   * Set the view to **Cards**.

## **AI-Assisted Vault Maintenance**

The **Librarian Agent** assists with organization and knowledge development. It proposes actions but **never modifies files without explicit approval.**

### **Interaction Protocol**

* **Vault Scope**: Agents work on one vault at a time. If context is missing, they will ask: *"Which vault should I work with?"*  
* **Pathing**: All paths are relative to the selected vault (e.g., vaults/\[name\]/SYS/...).  
* **Safety**: Agents require per-vault confirmation for structural changes.

### **Available Agents**

#### **Option A: GitHub Copilot (VSCode)**

1. Open your vault folder in VSCode.  
2. Ensure the GitHub Copilot extension is installed.  
3. Use the chat interface; it automatically detects definitions in .github/agents/.

#### **Option B: Gemini CLI**

1. Install [Gemini CLI](https://github.com/google/gemini-cli).  
2. Install the provided skill: gemini skills install ./librarian-vault-manager.skill \--scope workspace.  
3. Reload your session with /skills reload.

### **Librarian Commands**

| Command | Purpose |
| :---- | :---- |
| /construct-vault | Scaffolds a new system/structure through guided chat. |
| /daily-review | Identifies concepts mentioned 3+ times in journals for evergreen extraction. |
| /audit-links | Checks for orphaned notes and broken references. |
| /cleanup | Detects duplicates and naming inconsistencies. |
| /flashcards | Generates Anki-ready spaced repetition cards from your notes. |

## **System Architecture**

### **ACID Notation**

Every evergreen note uses Area, Category, and ID (ACID) notation with a system prefix: SYS.AC.ID.

| Component | Description | Range |
| :---- | :---- | :---- |
| SYS | System code | 2-4 letters (e.g., LIFE) |
| A | Area | 1-F (Hexadecimal) |
| C | Category | 1-F (Hexadecimal) |
| ID | Unique ID | 01-FF (Hexadecimal) |

**Example:** LIFE.3A.07 (LIFE system, Area 3, Category A, ID 07).

### **Deviations From Canonical Johnny Decimal**

* **Hexadecimal**: We use 1-F (16 slots) instead of 0-9 (10 slots) to maximize density.  
* **System Prefixes**: Allows multiple separate JD systems within one vault.  
* **Automated Indexes**: Using the **Bases** plugin to replace manual index maintenance.

### **Standard Zeros**

* The 00 area is reserved for system meta-information (indexes).  
* SYS.00.00 denotes the index file for a system.  
* 00.00 in the vault root is the master index.

### **Folder Structure**

```
VAULT/  
├── \_SYS/  
│   ├── JDEX\_00.00.base  
│   ├── JDEX\_LIFE.base  
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
└── 00.00.md                      ← Root index
```

### **Naming Conventions**

| Element | Pattern | Example |
| :---- | :---- | :---- |
| System folder | SYS/ | LIFE/ |
| Area folder | A0-Area Name/ | 10-Philosophy/ |
| Category folder | AC-Category Name/ | 11-Productivity/ |
| Note file | SYS.AC.ID-Title.md | LIFE.11.01-Title.md |

### **System Index Template**

The system index file (SYS.00.00.md) acts as the entry point for a specific system. It links back to the master index and embeds the relevant Base file:  
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

1. **Daily Capture**: Record raw thoughts in JRNL/YYYY/MM/YYYY-MM-DD.md. This is low-friction and transient.  
2. **Review & Extract**: Run /daily-review. When an idea matures, extract it to an evergreen note with a claim-based title and ACID ID.  
3. **Link & Connect**: Place \[\[links\]\] inline within sentences to explain context.  
4. **Audit**: Weekly, run /audit-links and /cleanup to maintain the "garden."

## **Advanced Deployment & Integration**

### **Dockerized Obsidian**

For a consistent environment, use the provided docker-compose.yml.

1. **Set Permissions**: Run id \-u and id \-g and update the PUID/PGID in docker-compose.yml.  
2. **Launch**: docker compose up \-d.  
3. **Access**: Navigate to https://localhost:3001.

### **Web Clipper**

Capture web content directly into your daily notes.

1. Install the **Obsidian Web Clipper** browser extension.  
2. **Docker Users**: Run ./setup-obsidian-uri.sh on your host.

### **Anki Integration**

1. Install **Anki** and the **AnkiConnect** add-on (code: 2055492159).  
2. Install the **Obsidian\_to\_Anki** community plugin.

## **External Resources**

* [Johnny Decimal Official Guide](https://johnnydecimal.com/)  
* [Zettelkasten Method Overview](https://zettelkasten.de/overview/)  
* [Andy Matuschak’s Evergreen Notes](https://notes.andymatuschak.org/z5E5QawiXCMbtNtupvxeoEX)
