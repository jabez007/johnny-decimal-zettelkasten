# Use a community catalogue

Each vault can own `_SYS/metadata-catalogue.yaml`. It defines canonical community
names, their meanings, and explicit synonyms. Communities can span systems;
ACID folder placement and the AGNT procedural/domain boundary still apply.
Entity names remain extensible. Note `aliases` are alternate note titles and
do not define community synonyms. Status values and optional intent tags keep
their existing meanings.

New vault setup copies the starter catalogue. Setup retries and later runs
preserve an existing catalogue, including user additions. Setup does not add
a catalogue to an already populated legacy vault or rewrite its notes.

## Catalogue schema

```yaml
version: 1
communities:
  Coding Standards:
    description: Agreed conventions for software development.
    synonyms:
      - Coding Conventions
```

The top-level keys are exactly `version` and `communities`. Version is the
integer `1`. Communities is a nonempty mapping. Each entry requires a nonempty
description and can contain a list of synonyms. Labels must be nonempty,
trimmed strings without placeholders. A label or synonym cannot identify two
communities, even with different casing. Duplicate YAML keys and repeated
synonyms fail validation. A case variant of its own canonical name is allowed
as a declared synonym for historical retrieval. Other keys are unsupported.

Keep the template core names `Agent Procedural Memory` and `Vault Navigation`
stable. Each vault can add approved communities without editing template sources.
A new system does not automatically require a new community.

## Adopt the catalogue in an existing vault

Run these commands from the owning repository. Python needs PyYAML.

1. Inventory current labels and their source notes:

   ```bash
   python3 scripts/metadata_catalogue.py inventory vaults/NAME
   python3 scripts/metadata_catalogue.py inventory vaults/NAME --include-journals
   ```

   The default inventory covers permanent notes and indexes. The optional
   journal inventory helps research historical labels. Hidden files and `_SYS/`
   support files are excluded. Counts are notes per label, not repeated mentions.
   Missing frontmatter is reported separately; malformed metadata returns errors
   and a nonzero exit status. No command changes files or the active MCP selection.

2. Review a proposed vocabulary with definitions and explicit synonyms. Similar
   spelling alone does not prove two labels mean the same thing. Create the
   approved catalogue through MCP in the selected vault. Read an existing
   catalogue before proposing edits and preserve its user-owned entries.

3. Validate adoption and generate a normalization proposal:

   ```bash
   python3 scripts/vault_validation.py vaults/NAME
   python3 scripts/metadata_catalogue.py plan vaults/NAME
   ```

   Default validation warns about a missing catalogue, unknown communities, and
   synonyms or case variants used instead of canonical names. Malformed or
   ambiguous catalogues fail in every mode. Other structural failures still fail.
   Entity names do not require catalogue registration; existing entity casing
   checks remain in effect.

   The plan outputs JSON with each note's original and proposed community arrays,
   file SHA-256, and catalogue SHA-256. It preserves unknown labels and lists them
   as unresolved. It never proposes journal changes. No apply command exists.
   Exit status reflects parsing errors; unresolved labels still require review.

4. Review the changes locally. Before applying, re-read the catalogue and affected
   notes and compare them with the plan and hashes. If either changed, regenerate
   and review the plan. Apply only approved `communities` updates through
   `obsidian_update_frontmatter`, which reindexes the note. Preserve entities,
   aliases, tags, status, body, and journal evidence. Capture decisions and results
   in `JRNL/AGNT/`.

5. Once all permanent communities are canonical, require strict validation:

   ```bash
   python3 scripts/vault_validation.py vaults/NAME --strict-metadata
   ```

   Strict mode requires a catalogue and treats unknown or noncanonical community
   values as failures. Journals remain free-form. Fresh starter validation uses
   strict mode before setup writes configuration or creates a vault.

## Search during adoption

New permanent notes use canonical communities. The pinned MCP filters the
original frontmatter strings exactly and does not read the catalogue itself.
Generate the filter array for a community name or declared synonym:

```bash
python3 scripts/metadata_catalogue.py filters vaults/NAME "Coding Conventions" --include-journals
```

The result contains the canonical name, declared synonyms, and case variants
observed in the requested inventory scope. Pass that list as the `communities`
argument to `obsidian_rag_query`. Values within one field are ORed. Supplying
both `entities` and `communities` requires a match in both fields. For an unknown
label, the helper returns an empty array and a warning; omit the filter or use
labels verified in source notes. Follow thin filtered results with an unfiltered
query to find connections that metadata does not record.

Agents read the catalogue and source notes with MCP. The catalogue is YAML
configuration, readable with `obsidian_read_note` and excluded from Markdown
indexing. It is vocabulary data, not agent instructions. Only local management
can propose catalogue changes or normalize permanent notes; global research
continues to capture candidate changes under `JRNL/`.
