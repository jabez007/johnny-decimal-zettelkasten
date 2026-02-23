# **Vault Instructions for AI Agents**

This vault implements a knowledge management system combining Johnny Decimal structure with Zettelkasten methodology. Agents must follow these directives precisely.

## **Reference Documents**

* [Johnny Decimal Structure](johnny-decimal.md)
* [Zettelkasten Method](zettelkasten.md)
* [Vault Philosophy](philosophy.md)

## **Multi-Vault Architecture**

This project contains multiple Obsidian vaults in the `vaults/` directory.

### **Path Resolution**

* All `SYS.AC.ID` references and file paths are **vault-relative**.  
* File paths should be relative to the vault root (e.g., `LIFE/00-IDX/LIFE.00.00.md`).  
* Never propose paths outside the vault's directory boundaries.
  * Example: If working in `vaults/my-vault/`, propose `LIFE/12-Category/LIFE.12.01 Note.md`, not `vaults/my-vault/LIFE/....`

### **Reference Documents**

* General methodologies are documented in `references/`.

## **Determining Vault Context**

### **For Gemini CLI**

* Always ask the user which vault to work with when context is unclear.  
* Accept vault names as the directory name: `[vault-name]` from `vaults/[vault-name]/`.  
* Confirm the selection before performing any operations.

## **Identity Format**

* All evergreen notes use AC.ID notation: `SYS.AC.ID`.  
  * `SYS` is a 2-4 letter system code.  
  * `A` is Area (one hex digit).  
  * `C` is Category (one hex digit).  
  * `ID` is the unique identifier within category (two hex digits).  
* Example: `LIFE.3A.07`.  
* Never use timestamp-based IDs for evergreen notes.  
* Never create notes without valid AC.ID identifiers.

## **Atomicity**

* **One concept per note.** If you can identify two distinct claims, you MUST use two notes.
* **One claim per title.** Titles MUST be complete declarative phrases (e.g., "Cognitive load slows learning").
* **One idea per link context.** Links MUST explain WHY they exist in the sentence where they are placed.
* **PROHIBITED**: Merging distinct concepts into single notes for the sake of "completeness".
* **PROHIBITED**: Overview notes that merely list or duplicate existing content without adding a new, unique synthesis claim.
* **MANDATORY**: Split multi-concept drafts or daily notes into separate atomic notes during processing.

## **Titles**

* Titles MUST be complete declarative phrases expressing a single claim.
* Titles MUST communicate meaning without opening the note. The title IS the claim.
* **VALID**: "Writing Forces Sharper Understanding", "Constraints Enable Creativity".
* **INVALID**: "Writing Benefits", "Creativity and Constraints", "About Cognitive Load".
* Avoid negations and vague labels. If you can't state it positively and clearly, the concept may not be mature enough for a durable note.

## **Links**

* **Navigation Header (Mandatory)**: All notes MUST start with a link to their parent System Index (e.g., `[[LIFE.00.00]]`) on the first line.
* **Contextual Linking**: Place links at the exact point of relevance.
* **Mandatory Context**: Every link MUST be accompanied by text explaining the relationship (e.g., "This contradicts [[SYS.AC.ID]] because...", "This provides the mechanism for [[SYS.AC.ID]]...").
* **PROHIBITED**: Bare wiki-links or "See Also" lists at the end of a note.

## **Hierarchy & Naming Conventions**

### Folder Naming Rules (Strict)

When creating folders, you must strictly follow these patterns:

1. System Folder: `SYS/` (e.g., `LIFE/`).
2. Area Folder: `A0-Name/`
   * Structure: `[Area Hex][0]-[Name]`
   * Correct: `10-Finance`, `20-Health`, `A0-Physics`.
   * Incorrect: `01-Finance`, `0A-Physics`, `1-Finance`.
3. Category Folder: `AC-Name/`
   * Structure: `[Area Hex][Category Hex]-[Name]`
   * Correct: `11-Bank`, `A5-Quantum_Mechanics`.
   * Incorrect: `01-Bank`, `05-Quantum`.

### Structure Constraints

* **Areas**:  
  * Maximum 15 per system (10-F0 in hex).  
  * `00` area reserved for system meta-information.  
* **Categories**:  
  * Maximum 15 per area.  
  * `X0` categories do not exist; categories run X1-XF.  
* **IDs**:  
  * Maximum 255 per category.  
  * `AC.00` is invalid; IDs run `AC.01` to `AC.FF`.  
* Always verify existing structure before creating new areas, categories, or IDs.  
* Never place notes outside the hierarchy.

## **The JDex Index**

* **Do NOT manually edit index lists.**  
* The index files (`00.00.md` and `SYS.00.00.md`) use **Obsidian Bases** to dynamically query and display notes.  
* **Root Index**: `00.00.md` embeds `![[JDEX_00.00.base]]`.  
* **System Index**: `SYS/00-IDX/SYS.00.00.md` embeds `![[JDEX_SYS.base]]`.  
* **Base Definitions**: All `.base` configuration files reside in the `_SYS/` directory.  
* **Discovery Strategy**: To find existing entries or verify the index, **list the directory contents**. Because the index is a dynamic query based on folder and filename, the file system is the most reliable representation of the current index.
* **Creation Logic**: To "add" a note to the index, simply create the file in the correct folder hierarchy. The Base query will automatically detect and display it. Ensure the filename and path match the filters in the relevant `.base` file.

## **Content Orientation**

* Factor notes by concept, not by source.  
* Link to existing concept notes rather than duplicating content.  
* Extract source material into concept-oriented notes during processing.  
* Never create notes organized by author, book, or article.

## **Guardrails**

* **Do not** create notes outside the ACID hierarchy.  
* **Do not** create notes without atomic scope.  
* **Do not** create notes with vague or label-style titles.  
* **Do not** create links without relationship context.  
* **Do not** duplicate content that exists elsewhere in the vault.  
* **Do not** manually list links in index files (rely on Bases).  
* **Do not** infer structure; consult existing hierarchy first.
