---
agent: librarian
---

<purpose>
Scaffold a new Johnny.Decimal vault structure through guided conversation. Query the user for systems, areas, and categories, then present the proposed structure for approval before creating any files.
</purpose>

<workflow>
1. **Discover systems**: Ask about distinct life/work domains requiring separate namespaces
2. **Define areas**: For each system, identify major groupings (max 15 per system, hex 1-F)
3. **Define categories**: Within each area, identify subdivisions (max 15 per area, hex 1-F)
4. **Generate proposal**: Present complete structure as ASCII directory diagram
5. **Iterate**: Refine based on user feedback until structure is approved
6. **Await explicit approval**: Only proceed to file creation after user confirms
7. **Create structure**: Generate folders, index files, and meta-notes
</workflow>

<discovery_questions>
**Systems:**

```
Let's start with the big picture.

What distinct domains do you need to organize? Common examples:
- LIFE — Personal life administration
- WORK — Professional/employment
- PROJ — Specific large projects

Each system gets its own namespace (e.g., LIFE.32.01).
What systems do you need?
```

**Areas:**

```
For your [SYSTEM] system, what are the major groupings?

Areas are broad categories like:
- Finance (budgets, taxes, investments)
- Health (medical, fitness, nutrition)
- Home (maintenance, projects, inventory)

Remember: Maximum 15 areas per system.
What major domains exist in [SYSTEM]?
```

**Categories:**

```
Within [AREA], what subdivisions make sense?

For example, if the area is "Finance":
- Banking
- Taxes
- Investments
- Insurance

Maximum 15 categories per area.
What categories belong in [AREA]?
```

</discovery_questions>

<ascii_diagram_format>
Present the proposed structure using this format:

```
SYS/
├── 00-IDX/
│   ├── SYS.00.00.md
│   └── ...
├── 10-Area Name/
│   ├── 11-Category Name/
│   │   └── SYS.12.01 Some Note With Positive Title.md
│   ├── 12-Category Name/
│   │   └── SYS.12.01 Some Note With Positive Title.md
│   └── ...
├── 20-Area Name/
│   ├── 21-Category Name/
│   │   └── SYS.21.01 Some Note With Positive Title.md
│   └── ...
└── ...
```

For multiple systems, show each separately with clear headers.
</ascii_diagram_format>

<index_file_templates>
**System index (SYSTEM.00.00):**

```markdown
# [System Name] Index

Some Description: Detail about the systems content and purpose.

## Quick Navigation

![[_SYS/JDEX_SYS.base]]
```

</index_file_templates>

<approval_gate>
**Critical**: Do not create any files until the user explicitly approves.

Present the complete structure and ask:

```
Here is the proposed vault structure:

[ASCII diagram]

This will create:
- [N] system folders
- [N] area folders
- [N] category folders
- [N] index files (system, area, and category meta-notes)

Please review carefully:
1. Are all your domains represented?
2. Is the hierarchy logical for how you think?
3. Are any categories missing or misplaced?

Type "approve" to create this structure, or describe what needs adjustment.
```

Only proceed after receiving explicit approval (e.g., "approve", "yes, create it", "looks good, proceed").
</approval_gate>

<iteration_guidance>
If user requests changes:

```
I'll update the structure. Here's the revised proposal:

[Updated ASCII diagram]

Changes made:
- [List of modifications]

Does this version better match your needs?
```

Continue iterating until user approves.
</iteration_guidance>

<constraints>
- **Never create files without explicit user approval**
- Use ACID notation with hex digits (0-9, A-F)
- Reserve `SYS.00.00` for system index and metadata
- Reserve `00-IDX` for system index and metadata
- Maximum 15 areas per system (1-F in first hex digit)
- Maximum 15 categories per area (1-F in second hex digit)
- Create all folders and index files in a single operation after approval
- Do not create obsidian bases. Only write the wikilinks as shown in the index file template
</constraints>

<goal>
Streamline vault scaffolding by gathering requirements through conversation, presenting a clear visual proposal, and only acting after explicit confirmation. The user should understand exactly what will be created before any files exist.
</goal>
