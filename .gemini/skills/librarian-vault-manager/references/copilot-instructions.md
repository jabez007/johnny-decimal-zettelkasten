# Vault Instructions for AI Agents

This vault implements a knowledge management system combining Johnny Decimal structure with Zettelkasten methodology. Agents must follow these directives precisely.

## Reference Documents

- [Johnny Decimal Structure](references/johnny-decimal.md)
- [Zettelkasten Method](references/zettelkasten.md)
- [Vault Philosophy](references/philosophy.md)

---

## Multi-Vault Architecture

This project contains multiple Obsidian vaults in the `vaults/` directory.

### Path Resolution
- All `SYS.AC.ID` references and file paths are vault-relative
- File paths should be relative to the vault root (e.g., `LIFE/00-IDX/LIFE.00.00.md`)
- Never propose paths outside the vault's directory boundaries
- Example: If working in `vaults/my-vault/`, propose `LIFE/12-Category/LIFE.12.01 Note.md` not `vaults/my-vault/LIFE/...`

### Reference Documents
- General methodologies are documented in `references/`

---

## Determining Vault Context

### For Gemini CLI
- Always ask the user which vault to work with when context is unclear
- Accept vault names as the directory name: `[vault-name]` from `vaults/[vault-name]/`
- Confirm the selection before performing any operations

---

## Identity Format

- All evergreen notes use AC.ID notation: `SYS.AC.ID`
    - `SYS` is a 2-4 letter system code
    - `A` is Area (one hex digit)
    - `C` is Category (one hex digit)
    - `ID` is the unique identifier within category (two hex digits)
- Example: `LIFE.3A.07`
- Never use timestamp-based IDs for evergreen notes
- Never create notes without valid AC.ID identifiers

---

## Atomicity

- One concept per note
- One claim per title
- One idea per link context
- Never merge distinct concepts into single notes
- Never create overview notes that duplicate existing content
- Split multi-concept drafts into separate atomic notes

---

## Titles

- Titles must be complete declarative phrases
- Titles must express a claim, not a label
- Valid: "Writing Forces Sharper Understanding"
- Invalid: "Writing Benefits"
- The title must communicate meaning without opening the note
- The Title must positively state concepts: avoid negations or vague terms

---

## Links

- Place links at the exact sentence where the connection applies
- Never use bare links without context
- Never use "see also" lists at note end
- Prefer explicit manual links over inferred associations

---

## Hierarchy

- Areas:
    - maximum 16 per system (10-F0 in hex)
    - `00` area reserved for system meta-information
- Categories:
    - maximum 16 per area
    - `X0` categories do not exist; categories run X1-XF
- IDs:
    - maximum 256 per category
    - `AC.00` is invalid; IDs run `AC.01` to `AC.FF`

- Always verify existing structure before creating new areas, categories, or IDs
- Never place notes outside the hierarchy

---

## The JDex Index

- The index is the authoritative registry of all IDs
- The index doubles as the structure note for navigation
- Consult the index before creating any new ID
- Update the index immediately after creating any new ID
- Never create orphaned IDs missing from the index
- This vault uses a root index file at `00.00` and system indices at `SYS/00-IDX/SYS.00.00`
- The id's are automatically tracked using obsidian bases that dynamically query each system
    - There is no need for manual tracking as the bases update automatically

---

## Content Orientation

- Factor notes by concept, not by source
- Link to existing concept notes rather than duplicating content
- Extract source material into concept-oriented notes during processing
- Never create notes organized by author, book, or article

---

## Guardrails

- **Do not** create notes outside the ACID hierarchy
- **Do not** create notes without atomic scope
- **Do not** create notes with vague or label-style titles
- **Do not** create links without relationship context
- **Do not** duplicate content that exists elsewhere in the vault
- **Do not** modify the index without corresponding note changes
- **Do not** create notes without corresponding index entries
- **Do not** infer structure; consult existing hierarchy first
