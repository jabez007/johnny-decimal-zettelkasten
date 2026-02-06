# Second Brain: A Compounding Knowledge System

Most notes are transient—written and forgotten. This system makes knowledge compound over time. Each note you write becomes part of an interconnected network where insights build upon each other, and every hour of thinking leaves something behind that makes future thinking easier.

This vault combines **Johnny Decimal** for structural organization with **Zettelkasten** for emergent meaning through connections, augmented by an AI librarian agent for maintenance.

---

## Baseline Setup: Obsidian Notes

### Obsidian

Obsidian is the primary interface for reading, writing, and navigating the vault.

#### **Installation:**

1. Download from [obsidian.md](https://obsidian.md/)
2. Create a new vault or open an existing folder as a vault
3. Place the contents of this `.github` folder in the vault root

#### **Required Feature — Obsidian Bases:**

Obsidian Bases is a core plugin that enables database-like views of your notes. It replaces manual index maintenance with dynamic queries that automatically track all notes in each system.

1. Open Settings → Core Plugins
2. Enable "Bases"

Reference: [Obsidian Bases Documentation](https://help.obsidian.md/bases)

---

### Dockerized Obsidian

For a quick and consistent way to run Obsidian, you can use the provided Docker Compose setup. This uses the `linuxserver/obsidian` image.

#### Setup

1.  **Ensure Docker and Docker Compose are installed.**
2.  **`docker-compose.yml`**: This file is already in the repository root. It defines the Obsidian service.
3.  **`config/` directory**: This directory (also in the repository root) is mapped to `/config` inside the container. It is primarily for Obsidian's global application settings (which are minimal) and specific files the `linuxserver/obsidian` image might use.
    *   *Note*: Most Obsidian settings (themes, plugins, hotkeys) are **vault-specific** and stored within the `.obsidian` folder of each vault.
4.  **`vaults/` directory**: This directory (also in the repository root) is mapped to `/vaults` inside the container. This is where you will place your Obsidian vaults.
    *   A `vaults/default-vault/` has been created with a baseline configuration, including dark mode, and enabled "Backlinks", "Obsidian Bases", and "Daily Notes" core plugins.
    *   To use this pre-configured vault, select it when Obsidian first launches.
    *   To use an existing vault, copy its entire folder (e.g., `my-existing-vault/`) into the `vaults/` directory. If you want it to use the baseline config, copy the contents of `vaults/default-vault/.obsidian/` into your existing vault's `.obsidian/` folder.
    *   If you are starting fresh with a new vault, you can create an empty folder inside `vaults/` (e.g., `vaults/my-new-vault/`). Obsidian will prompt you to create a new vault or open an existing one when you first access it. You can then copy the `.obsidian` folder from `vaults/default-vault/` into your new vault for the baseline configuration.

#### Configuration

The `docker-compose.yml` includes environment variables that you **must** customize:

*   **`PUID` and `PGID`**: These should match your host user's User ID (UID) and Group ID (GID) to prevent file permission issues between your host and the container.
    *   You can find your `PUID` by running `id -u` in your terminal.
    *   You can find your `PGID` by running `id -g` in your terminal.
*   **`TZ`**: Set this to your local timezone (e.g., `America/New_York`).
*   **`UMASK_SET`**: (Optional) Sets the file creation mask. `022` is a common value.

**Example `docker-compose.yml` snippet after customization:**

```yaml
services:
  obsidian:
    environment:
      - PUID=1000 # Your actual UID
      - PGID=1000 # Your actual GID
      - TZ=America/New_York
```

#### Usage

1.  **Navigate to the repository root** in your terminal where `docker-compose.yml` is located.
2.  **Start the Obsidian container**:
    ```bash
    docker compose up -d
    ```
    This command will download the `linuxserver/obsidian` image (if not already present) and start the container in detached mode (in the background).
3.  **Access Obsidian**:
    *   Open your web browser and navigate to `http://localhost:3000` (for HTTP) or `https://localhost:3001` (for HTTPS).
    *   The first time you access it, Obsidian may prompt you to open an existing vault or create a new one. Select the vault you placed in the `vaults/` directory (e.g., `/vaults/my-vault`).
4.  **Stop the container**:
    ```bash
    docker compose down
    ```
5.  **Remove container and volumes (optional)**:
    ```bash
    docker compose down -v
    ```

This setup ensures your Obsidian notes and configurations are persistent on your host machine, even if you recreate the container.

---

##### **Creating Base Files:**

Base files (`.base`) are created and edited through the Obsidian UI, not as raw text.

1. Right-click the `_SYS/` folder in the File Explorer
2. Select **New base**
3. Name the file (e.g., `JDEX_LIFE`)

##### **Configuring Filters (via UI):**

1. Open the base file
2. Click the **Filter** icon in the toolbar
3. Under "All views", add filter conditions:
    - Property: `file.folder` | Operator: `contains` | Value: `LIFE`
    - Add another condition to exclude index folders as needed
4. Filters update automatically as you configure them

##### **Configuring Views (via UI):**

1. Click the view name in the top-left of the base
2. Select **Add view** or click the arrow next to an existing view to configure it
3. Choose a layout type:
    - **Table**: Rows of files with property columns (use for system indexes)
    - **Cards**: Grid layout with images (use for root index)
    - **List**: Bulleted/numbered file lists

##### **Required Base Files:**

| File              | Location | Purpose                                    | Recommended View |
| ----------------- | -------- | ------------------------------------------ | ---------------- |
| `JDEX_00.00.base` | `_SYS/`  | Root index — shows all system indexes      | Cards            |
| `JDEX_[SYS].base` | `_SYS/`  | System index — shows all notes in a system | Table            |

##### **Root index filter configuration:**

- Property: `file.name` | Operator: `ends with` | Value: `.00.00`

##### **System index filter configuration (example for LIFE):**

- Condition 1: Property: `file.folder` | Operator: `contains` | Value: `LIFE`
- Condition 2: Property: `file.folder` | Operator: `does not contain` | Value: `00-IDX`

##### **Embedding Bases in Index Notes:**

Base files are embedded in index notes using Obsidian's standard embed syntax:

```markdown
![[JDEX_LIFE.base]]
```

This renders the base's first view inline within the note. To embed a specific view, use `![[JDEX_LIFE.base#ViewName]]`.

#### **Required Feature — Backlinks:**

Backlinks reveal which notes reference the current note. This is essential for Zettelkasten-style knowledge work, where meaning emerges through connections.

1. Open Settings → Core Plugins
2. Enable "Backlinks"

##### **Viewing Backlinks:**

- Click the **Backlinks** tab in the right sidebar to see all notes linking to the current note
- **Linked mentions**: Notes containing explicit `[[wiki-links]]` to this note
- **Unlinked mentions**: Notes containing the note's name as plain text (potential links)

##### **Recommended Setting:**

Enable "Backlink in document" in the Backlinks plugin options. This displays backlinks at the bottom of each note, making connections visible without opening the sidebar.

Reference: [Obsidian Backlinks Documentation](https://help.obsidian.md/plugins/backlinks)

#### **Recommended — Obsidian Web Clipper:**

Web Clipper is a browser extension for capturing web content directly into your vault. It supports highlighting, templates, and metadata extraction.

##### **Web Clipper Installation:**

1. Install the extension for your browser:
    - [Chrome / Brave / Arc](https://chromewebstore.google.com/detail/obsidian-web-clipper/cnjifjpddelmedmihgijeibhnjfabmlf)
    - [Firefox](https://addons.mozilla.org/en-US/firefox/addon/web-clipper-obsidian/)
    - [Safari](https://apps.apple.com/us/app/obsidian-web-clipper/id6720708363)
    - [Edge](https://microsoftedge.microsoft.com/addons/detail/obsidian-web-clipper/eigdjhmgnaaeaonimdklocfekkaanfme)
2. Enable the Daily Notes core plugin in Obsidian (Settings → Core Plugins → Daily Notes)

##### **Recommended Configuration — Append to Daily Note:**

Configure Web Clipper to append clippings to your current daily note. This keeps captures in your transient journal for later processing into evergreen notes.

1. Click the Web Clipper extension icon → Settings (gear icon)
2. Create or edit a template
3. Under **Behavior**, select "Add to daily note" → "Bottom"
4. Customize the template content as needed

This workflow ensures web captures flow through the same refinement pipeline as other daily observations: capture → review → extract to evergreen notes.

Reference: [Obsidian Web Clipper Documentation](https://help.obsidian.md/web-clipper)

---

## AI-Assisted Vault Maintenance

This vault leverages AI agents to assist with maintenance, organization, and knowledge development. These agents propose actions and insights based on the vault's structure and content, but **never modify files without explicit user approval.**

### GitHub Copilot Librarian Agent

VSCode with GitHub Copilot provides AI-assisted vault maintenance through the Librarian agent.

#### **Setup:**

1. Install [VSCode](https://code.visualstudio.com/)
2. Install the GitHub Copilot extension
3. The `.github` folder in your vault root contains the agent and prompt definitions
4. Open the vault folder in VSCode

No additional configuration is required. Copilot automatically detects agent files in `.github/agents/` and prompt files in `.github/prompts/`.

### Gemini CLI Librarian Agent

The Gemini CLI Librarian Agent extends AI-assisted vault maintenance to your command line. It provides similar functionalities to the Copilot agent, focusing on structural integrity and knowledge development within your Johnny Decimal and Zettelkasten vault.

#### **Installation:**

1. Ensure you have [Gemini CLI](https://github.com/google/gemini-cli) installed and configured.
2. The `librarian-vault-manager.skill` file has been generated in your project root. Install it with workspace scope:

    ```bash
    gemini skills install ./librarian-vault-manager.skill --scope workspace
    ```

3. **Important:** After installation, you must reload your Gemini CLI session by running `/skills reload` in your interactive Gemini CLI. You can verify installation with `/skills list`.

#### **Usage:**

Once installed and reloaded, invoke the Librarian Agent directly in your Gemini CLI session. The agent will respond to various queries related to vault management.

**Invoke the Librarian in Gemini CLI with prompts like:**

- "organize my vault"
- "check my index"
- "review daily notes"
- "audit links"
- "cleanup notes"
- "create new vault section"
- "generate flashcards"

### Available Prompts (for both Copilot and Gemini CLI)

The underlying prompts are shared and facilitate various maintenance tasks:

#### `/construct-vault`

Scaffolds a new vault structure through guided conversation. Use when setting up a new system or restructuring an existing one.

```text
/construct-vault Help me create a new system for my research projects
```

#### `/daily-review`

Extracts durable knowledge from transient daily notes. Identifies concepts mentioned 3+ times across recent entries and proposes evergreen notes.

```text
/daily-review Scan this week's journal entries
```

#### `/audit-links`

Analyzes link health across the vault. Identifies orphaned notes, broken references, and opportunities for meaningful connections.

```text
/audit-links Check connection health in TECH system
```

#### `/cleanup`

Detects duplicates, naming inconsistencies, and misplaced notes. All cleanup preserves information through consolidation, never deletion.

```text
/cleanup Scan for duplicate concepts
```

#### `/flashcards`

Generates spaced repetition flashcards from note content. Appends cards to a `# Questions` section for export to Anki.

```text
/flashcards Generate for TECH.12.01
```

---

## Core Concepts

### Johnny Decimal

Johnny Decimal provides predictable file location through hierarchical numbering. Every note has an unambiguous home. The structure eliminates the paralysis of infinite filing options and makes retrieval predictable.

- **Systems**: Top-level domains (LIFE, WORK, TECH). Identified by 3-4 letter codes.
- **Areas**: Major groupings within a system. Maximum 16 per system.
- **Categories**: Subdivisions within an area. Maximum 16 per area.
- **IDs**: Individual notes. Maximum 256 per category.

Reference: [johnnydecimal.com](https://johnnydecimal.com/)

### Zettelkasten

Zettelkasten creates emergent insight through explicit links between notes. Links carry meaning—they explain _why_ connections exist, not just _that_ they exist.

- Each note contains one atomic idea
- Notes link to related notes through explicit references
- The network reveals relationships across domains

Reference: [zettelkasten.de/overview](https://zettelkasten.de/overview/)

### Evergreen Notes

Evergreen notes are durable knowledge units designed for long-term value. Unlike transient captures, they are:

- **Atomic**: One concept per note
- **Concept-oriented**: Factored by idea, not by source
- **Claim-titled**: Titles express complete thoughts, not labels
- **Densely linked**: Connected to other notes with context

A title like "Writing forces sharper understanding" is a claim you can build upon. A title like "Writing benefits" is a label that communicates nothing.

Reference: [Andy Matuschak's Evergreen Notes](https://notes.andymatuschak.org/z5E5QawiXCMbtNtupvxeoEX)

### Why Combine These Systems

Johnny Decimal answers "where does this live?" through hierarchy. Zettelkasten answers "what connects to what?" through association. These layers are complementary:

- Hierarchy handles organization
- Association handles insight

A note in `TECH.12.01` can link to notes in `LIFE.34.07` and `QOC.71.03`—connections invisible to the hierarchy but essential to understanding.

---

## Vault Structure

### ACID Notation

Every evergreen note uses ACID (Area, Category, ID) notation with a system prefix:

```text
SYS.AC.ID
```

| Component | Description       | Range       |
| --------- | ----------------- | ----------- |
| `SYS`     | System code       | 2-4 letters |
| `A`       | Area              | 1-F (hex)   |
| `C`       | Category          | 1-F (hex)   |
| `ID`      | Unique identifier | 01-FF (hex) |

**Example:** `LIFE.3A.07` = LIFE system, Area 3, Category A, ID 07

### Folder Structure

```text
VAULT/
├── .github/
│   ├── agents/
│   │   └── librarian.agent.md
│   ├── prompts/
│   │   ├── audit-links.prompt.md
│   │   ├── cleanup.prompt.md
│   │   ├── construct-vault.prompt.md
│   │   ├── daily-review.prompt.md
│   │   └── flashcards.prompt.md
│   └── reference/
│       ├── johnny-decimal.md
│       ├── philosophy.md
│       └── zettelkasten.md
├── _SYS/
│   ├── JDEX_00.00.base
│   ├── JDEX_LIFE.base
│   └── TMPL/
│       └── Daily.md
├── LIFE/
│   ├── 00-IDX/
│   │   └── LIFE.00.00.md        ← System index
│   ├── 10-Area Name/
│   │   ├── 11-Category Name/
│   │   │   └── LIFE.11.01-Note Title.md
│   │   └── 12-Category Name/
│   │       └── LIFE.12.01-Note Title.md
│   └── 20-Area Name/
│       └── 21-Category Name/
│           └── LIFE.21.01-Note Title.md
├── JRNL/
│   └── YYYY/
│       └── MM/
│           └── YYYY-MM-DD.md    ← Daily notes
└── 00.00.md                     ← Root index
```

### Naming Conventions

| Element         | Pattern              | Example                        |
| --------------- | -------------------- | ------------------------------ |
| System folder   | `SYS/`               | `LIFE/`                        |
| Area folder     | `A0-Area Name/`      | `10-Philosophy/`               |
| Category folder | `AC-Category Name/`  | `11-Productivity/`             |
| Note file       | `SYS.AC.ID-Title.md` | `LIFE.11.01-Johnny.Decimal.md` |
| System index    | `SYS.00.00.md`       | `LIFE.00.00.md`                |
| Root index      | `00.00.md`           | `00.00.md`                     |

### Standard Zeros

- The `00` area is reserved for system meta-information (indexes)
- `SYS.00.00` denotes the index file for a system
- `00.00` in the vault root is the master index

### Index Files

Every note begins with a link to its system index:

```markdown
[[LIFE/00-IDX/LIFE.00.00]]

# Note Title

Content...
```

System index files embed their corresponding base file for dynamic navigation:

```markdown
[[00.00]]

# LIFE System Index

Description of this system's purpose.

## Quick Navigation

![[JDEX_LIFE.base]]
```

---

## Key Deviations From Cannonical Systems

This vault adapts Johnny Decimal and Zettelkasten with specific modifications:

| Standard System                         | This Vault                                                        |
| --------------------------------------- | ----------------------------------------------------------------- |
| Decimal numbering (10 areas/categories) | Hexadecimal numbering (16 areas/categories)                       |
| Single namespace                        | System prefixes for multi-domain support (`LIFE.`, `TECH.`, etc.) |
| Manual index maintenance                | Automatic tracking via Obsidian Bases                             |
| Human-only curation                     | AI-assisted maintenance via Librarian agent                       |

### Hex Numbering

Standard Johnny Decimal uses decimal (00-99). This vault uses hexadecimal (00-FF), allowing:

- 16 areas per system (1-F, with 0 reserved for meta)
- 16 categories per area (1-F)
- 256 IDs per category (01-FF)

### System Prefixes

Multi-domain support through 3-4 letter system codes enables clean separation between life domains while allowing cross-domain linking.

### Automatic Index Tracking

Base files eliminate manual index maintenance. When you create a note in `LIFE/10-Philosophy/11-Productivity/`, it automatically appears in the LIFE system index.

Bases do not physically link the tasks in a way that traditional indicies do so certain features that rely on physical links (backlinks, graph view, etc) may not function as expected. **This is a conscious trade-off to leverage automation while accepting some limitations in link-based features.**

---

## The Librarian Agent

The Librarian is a knowledge steward that maintains vault integrity and guides note development. It proposes actions but never modifies files without explicit approval.

**Invoke the Librarian in VSCode Copilot Chat with prompts like:**

- "organize my vault"
- "check my index"
- "review daily notes"
- "audit links"

### Available Prompts

#### `/construct-vault`

Scaffolds a new vault structure through guided conversation. Use when setting up a new system or restructuring an existing one.

```text
/construct-vault Help me create a new system for my research projects
```

#### `/daily-review`

Extracts durable knowledge from transient daily notes. Identifies concepts mentioned 3+ times across recent entries and proposes evergreen notes.

```text
/daily-review Scan this week's journal entries
```

#### `/audit-links`

Analyzes link health across the vault. Identifies orphaned notes, broken references, and opportunities for meaningful connections.

```text
/audit-links Check connection health in TECH system
```

#### `/cleanup`

Detects duplicates, naming inconsistencies, and misplaced notes. All cleanup preserves information through consolidation, never deletion.

```text
/cleanup Scan for duplicate concepts
```

#### `/flashcards`

Generates spaced repetition flashcards from note content. Appends cards to a `# Questions` section for export to Anki.

```text
/flashcards Generate for TECH.12.01
```

---

## Workflow

### Daily Capture

Raw thoughts, observations, and fragments go into daily notes:

```text
JRNL/YYYY/MM/YYYY-MM-DD.md
```

Daily notes are transient—zero friction, zero judgment. They serve as release valves for thinking-in-progress.

### Review and Extract

Periodically run `/daily-review` to identify concepts that have earned permanence. When an idea appears 3+ times or develops significant depth, extract it into an evergreen note with:

- A claim-based title
- An ACID identifier
- Links to related notes

### Link and Connect

Place links at the exact sentence where connections apply. Avoid "see also" lists. Each link should explain why the connection matters.

### Periodic Maintenance

Review and edit notes constantly. This system gets better the more you engage, explore, and contribute to it. Nothing is final—everything evolves.

Run `/audit-links` to identify orphaned notes and connection opportunities. Run `/cleanup` to detect duplicates and naming inconsistencies.

---

## Getting Started

1. **Install Obsidian** from [obsidian.md](https://obsidian.md/)

2. **Create a new vault** or open an existing folder

3. **Place `.github` folder** in the vault root

4. **Enable Obsidian Bases**
    - Settings → Core Plugins → Enable "Bases"

5. **Create the `_SYS` folder** in the vault root

6. **Create the root index** (`00.00.md`):

    ```markdown
    # Vault Index

    ![[JDEX_00.00.base]]
    ```

7. **Create the root base file**:
    - Right-click `_SYS/` → New base → Name it `JDEX_00.00`
    - Click the Filter icon → Add filter:
        - Property: `file.name` | Operator: `ends with` | Value: `.00.00`
    - Click the view name → Configure as Cards view

8. **(Optional) Set up an AI Librarian Agent**: Refer to the "AI-Assisted Vault Maintenance" section for details on setting up either the GitHub Copilot or Gemini CLI Librarian Agent.

9. **Invoke the Librarian Agent's `/construct-vault` prompt** to scaffold your first system through guided conversation

---

## Quick Reference

### ACID Format

```text
SYS.AC.ID
 │   │  └── Unique ID (01-FF)
 │   └───── Area (1-F) + Category (1-F)
 └───────── System code (2-4 letters)
```

### File Naming

```text
SYS.AC.ID-Descriptive Claim Title.md
```

### Note Template

```markdown
[[SYS/00-IDX/SYS.00.00]]

# Descriptive Claim Title

Content expressing a single atomic concept.

Links placed [[inline]] where the connection applies.
```

### Base File Setup

Create base files through the Obsidian UI (right-click folder → New base).

| Base File           | Filter Property | Operator         | Value    |
| ------------------- | --------------- | ---------------- | -------- |
| Root index          | `file.name`     | ends with        | `.00.00` |
| System index        | `file.folder`   | contains         | `$SYS`   |
| (add second filter) | `file.folder`   | does not contain | `00-IDX` |

Embed in index notes: `![[JDEX_$SYS.base]]`

---

## Appendix: Anki Integration (Optional)

Anki provides spaced repetition for long-term memory retention. This integration is optional and fully decoupled from the core vault system.

### Why Spaced Repetition?

Memory decays predictably. Spaced repetition interrupts this decay by prompting review at optimal intervals. Combined with a knowledge vault, it ensures important concepts remain accessible in working memory.

Reference: [Augmenting Long-term Memory](https://augmentingcognition.com/ltm.html)

### Required Software

**Anki:**

1. Download from [apps.ankiweb.net](https://apps.ankiweb.net/)
2. Install and create a profile

**AnkiConnect Plugin (for Anki):**

1. Open Anki → Tools → Add-ons → Get Add-ons
2. Enter code: `2055492159`
3. Restart Anki

**Obsidian_to_Anki Plugin:**

1. In Obsidian: Settings → Community Plugins → Browse
2. Search "Obsidian_to_Anki" → Install → Enable
3. Configure the plugin settings:
    - Set your Anki deck name
    - Configure regex patterns for card detection

### Card Formats

The `/flashcards` prompt generates two formats:

**Simple Q&A:**

```text
Question text here::Answer text here
```

**Cloze deletion:**

```text
The capital of France is ==Paris==
```

With hint:

```text
The capital of France is ==Paris==^[city name]
```

### Anki Workflow

1. Run `/flashcards` on an evergreen note
2. Review generated cards in the `# Questions` section
3. Open Anki (AnkiConnect must be running)
4. In Obsidian, run the Obsidian_to_Anki sync command
5. Cards appear in your configured Anki deck

---

## External Resources

### Systems and Methods

- [Johnny Decimal](https://johnnydecimal.com/) — File organization system
- [Zettelkasten.de](https://zettelkasten.de/overview/) — Networked note-taking method
- [Evergreen Notes](https://notes.andymatuschak.org/z5E5QawiXCMbtNtupvxeoEX) — Andy Matuschak's note philosophy
- [Taxonomy of Note Types](https://notes.andymatuschak.org/zTDjZQbKAT9pALtsk2HfePx) — Distinguishing transient from durable notes
- [Augmenting Long-term Memory](https://augmentingcognition.com/ltm.html) — Michael Nielsen's essay on spaced repetition

### Tools

- [Obsidian](https://obsidian.md/) — Knowledge base application
- [Anki](https://apps.ankiweb.net/) — Spaced repetition flashcards
- [VSCode + Copilot](https://code.visualstudio.com/docs/copilot/overview) — AI-assisted development
