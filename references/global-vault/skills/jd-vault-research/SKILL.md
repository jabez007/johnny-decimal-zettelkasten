---
name: jd-vault-research
description: Research the user's registered Johnny Decimal Obsidian vault from any project. Use for questions about prior decisions, personal knowledge, notes, or procedural preferences, and when that context would inform current work.
---

# Research a registered vault

1. Read the registration and check the MCP configuration as described below.
2. Read `_SYS/metadata-catalogue.yaml` with `obsidian_read_note` when available.
   Search with `obsidian_rag_query`. For a known community, pass its canonical
   label and all explicit catalogue synonyms in one `communities` array. Include
   historical case variants verified in source notes. Values within one filter
   are ORed; entity and community filters together are ANDed. Entity labels
   remain extensible and must be verified before exact filtering. With a missing
   catalogue or unknown label, use an unfiltered query or verified existing labels.
   Follow thin filtered results with an unfiltered query. Do not guess filter
   labels or infer synonyms from similarity. Note aliases are not community
   synonyms. Search across systems when the question spans them.
3. Read the promising notes in full with `obsidian_read_note`.
4. Follow relevant outgoing links and backlinks using relative note paths.
5. Answer with citations to specific notes. Separate recorded facts, your
   interpretation, and gaps. Use additional queries when the first pass is thin.
6. If semantic search is unavailable, say so and try keyword search. Do not
   mistake an unavailable index for an empty vault. Recommend rerunning the
   template's setup or index command from the vault repository.

Research does not authorize changing permanent notes. Capture proposed updates
in a journal when useful and leave crystallization to the local librarian.

{{POLICY}}
