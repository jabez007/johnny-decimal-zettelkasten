---
agent: librarian
---

\<purpose\>
Scaffold a new Johnny.Decimal vault structure through guided conversation. Query the user for systems, areas, and categories, then present the proposed structure for approval before creating any files.
\</purpose\>  

\<workflow\>
1. **Discover scope**: Determine if this is a brand new vault (requires root setup) or a new system within an existing vault.  
2. **Discover systems**: Ask about distinct life/work domains requiring separate namespaces.  
3. **Define areas**: For each system, identify major groupings (max 16 per system, hex 1-F).  
4. **Define categories**: Within each area, identify subdivisions (max 16 per area, hex 0-F).  
5. **Generate proposal**: Present complete structure as ASCII directory diagram including \_SYS and index files.  
6. **Iterate**: Refine based on user feedback until structure is approved.  
7. **Await explicit approval**: Only proceed to file creation after user confirms.  
8. **Create structure**: Generate folders, index files (00.00.md, {SYS}.00.00.md), and initial .base files.
\</workflow\>

\<discovery\_questions\>
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
For your {SYSTEM} system, what are the major groupings?

Areas are broad categories like:  
- Finance (budgets, taxes, investments)  
- Health (medical, fitness, nutrition)  
- Home (maintenance, projects, inventory)

Remember: Maximum 16 areas per system.  
What major domains exist in {SYSTEM}?
```
**Categories:**
```
Within {AREA}, what subdivisions make sense?

For example, if the area is "Finance":  
- Banking  
- Taxes  
- Investments  
- Insurance

Maximum 16 categories per area.  
What categories belong in {AREA}?
```
\</discovery\_questions\>  

\<ascii\_diagram\_format\>
Present the proposed structure using this format. Ensure \_SYS and 00.00.md are included if missing.  
```
VAULT_ROOT/
├── _SYS/  
│   ├── JDEX_00.00.base  
│   ├── JDEX_{SYS}.base  
│   └── TMPL/  
├── {SYS}/  
│   ├── 00-IDX/  
│   │   └── {SYS}.00.00.md  
│   ├── 10-Area Name/  
│   │   ├── 11-Category Name/  
│   │   │   └── {SYS}.12.01 Some Note With Positive Title.md  
│   │   └── ...  
│   └── ...  
├── JRNL/  
└── 00.00.md
```
\</ascii\_diagram\_format\>  

\<file\_templates\>
**Root Index (00.00.md):** Required if it does not exist.  
```
# Vault Index

![[JDEX_00.00.base]]
```
**System Index ({SYS}/00-IDX/{SYS}.00.00.md):** Note the link back to root at the top.  
```
[[00.00]]

# {System Name} Index

Description: [Brief description of system purpose]

## Quick Navigation

![[JDEX_{SYS}.base]]
```
**Root Base File (\_SYS/JDEX\_00.00.base):** Standard YAML configuration for the root index view.  
```
filters:  
  and:  
    - file.name.endsWith(".00.00")  
views:  
  - type: cards  
    name: Cards
```
**System Base File (\_SYS/JDEX\_{SYS}.base):** Standard YAML configuration for system index views.  
```
filters:  
  and:  
    - file.folder.contains("{SYS}")  
    - '!file.folder.contains("00-IDX")'  
views:  
  - type: table  
    name: Table
```
\</file\_templates\>

\<approval\_gate\>
**Critical**: Do not create any files until the user explicitly approves.  
Present the complete structure and ask:
```
Here is the proposed vault structure:

[ASCII diagram]

This will create:  
- [N] system folders  
- [N] area folders  
- [N] category folders  
- Index files: Root (00.00.md) and System ({SYS}.00.00.md)  
- Base configuration files in _SYS/

Please review carefully:  
1. Are all your domains represented?  
2. Is the hierarchy logical for how you think?  
3. Are any categories missing or misplaced?

Type "approve" to create this structure, or describe what needs adjustment.
```
Only proceed after receiving explicit approval (e.g., "approve", "yes, create it", "looks good, proceed").
\</approval\_gate\>  

\<constraints\>
* **Never create files without explicit user approval**  
* Use ACID notation with hex digits (0-9, A-F)  
* Reserve SYS.00.00 for system index and metadata  
* Reserve 00-IDX for system index and metadata  
* Root index 00.00.md must strictly contain \!\[\[JDEX\_00.00.base\]\]  
* System index must link to root \[\[00.00\]\] on the first line  
* Maximum 16 areas per system (1-F in first hex digit)  
* Maximum 16 categories per area (0-F in second hex digit)  
* Create all folders and index files in a single operation after approval
\</constraints\>

\<goal\>
Streamline vault scaffolding by gathering requirements through conversation, presenting a clear visual proposal, and only acting after explicit confirmation. Ensure the vault is fully initialized with working indexes and Base configurations.
\</goal\>
