# Johnny Decimal File Indexing System

## Overview

Johnny Decimal is a system for organizing information using a structured numerical hierarchy. It provides a predictable location for every item, enabling rapid retrieval and eliminating the cognitive load of remembering where things are stored.

## Core Philosophy

- **Everything has a place.** No item exists outside the system.
- **Structure over memory.** The system removes the need to remember information explicitly, relying instead on only remembering how to navigate the structure.
- **Simplicity enforces discipline.** Constraints prevent sprawl and maintain order.

## Hierarchical Structure

### Systems

Systems are the highest level of organization. Each system represents a distinct domain or area of life (e.g. Personal, Jobs, Projects, etc). You can have multiple systems, but each system sub-structure operates independently.

Systems are identified by a short 3-4 letter code (e.g., `HOME`, `JOB`, `LIFE`).

### Areas

Areas are the broadest groupings within a system. Each area spans a range of hexadecimal numbers (e.g., 10-1F). A system may have at most **16 areas** (10 through F0). Areas represent major system domains.

**Standard Zero**: The `00` area is reserved for meta-information about the containing system.

### Categories

Within each area, up to sixteen categories exist. Categories are two-digit numbers. They group related items under a common theme within their parent area.

The first digit of the category is the area number, and the second digit is the category number within that area (e.g., 11, 12, ..., 1F).

### IDs

Each category contains up to 256 unique IDs. An ID is a two-part hexadecimal number: `AC.ID` (e.g., `1F.05`). IDs represent specific things, topics, or discrete units of information.

**Format:** `AC.ID` where:

- `AC` = Area + Category (two digits)
- `ID` = Unique identifier within the category (two digits)

## ACID Notation

ACID (Area, Category, ID) notation extends the base format for multi-project or multi-system use:

**Format:** `SYS.AC.ID`

- `SYS` = System code
- `AC.ID` = Standard Johnny Decimal ID

This allows namespacing multiple systems (e.g., `HOME.32.07` for a home system, `QOC.32.07` for work at QOC).

## The JDex Index

The JDex is the authoritative index/registry of all IDs in your system. It is a single document listing every ID with its title. The JDex serves as:

- A reference to find any item's location
- A record of what exists in the system
- The source of truth when creating new IDs

Maintain the index in a plain text file, spreadsheet, or dedicated app. Consult it before creating new items.

## Workflow: Creating and Saving Files

1. **Determine the item's nature.** What is this thing about?
2. **Identify the area and category.** Where does it logically belong?
3. **Check the index.** Does an ID already exist for this item?
4. **Create or reuse an ID.** If no ID exists, assign the next available number in the category and add it to the index.
5. **Use the ID in the filename.** Prefix files with their ID for findability (e.g., `11.05-Some Title.md`).

## Keeping Notes

Notes attach to IDs. Each ID may have one associated note containing all relevant information for that item. Store notes in a consistent location.The ID is the prefix of a note's title.

## The Librarian Principle

Adopt the mindset of a librarian: every item must be catalogued before it enters the system. This discipline prevents orphaned files and ensures the index remains accurate.

## Building Your System

1. **Audit existing files.** Identify what you have.
2. **Define areas.** Group major domains (limit: 16).
3. **Define categories.** Subdivide areas into logical groupings (limit: 16 per area).
4. **Assign IDs.** Create IDs as needed; do not pre-allocate.
5. **Create the index.** Document every ID.
6. **Migrate files.** Move existing items into the new structure.
7. **Maintain discipline.** Always consult and update the index.

## Key Constraints

| Element             | Maximum Count |
| ------------------- | ------------- |
| Areas               | 16            |
| Categories per Area | 16            |
| IDs per Category    | 256           |

These limits enforce thoughtful organization and prevent unbounded complexity.
