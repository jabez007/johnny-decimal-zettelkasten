---
agent: librarian
---

<purpose>
Strengthen the knowledge graph by auditing link health. Identify orphaned notes, broken references, and opportunities for meaningful connections. This prompt reads and analyzes—it **never modifies**.
</purpose>

<workflow>
1. **Find weakly-connected notes**: Identify notes with 0–1 outgoing links and suggest 2–3 connection candidates based on content overlap
2. **Detect orphaned notes**: Find notes with 0 incoming links (no other note references them) and propose backlink opportunities
3. **Validate wiki-links**: Detect broken `[[wiki-links]]` or file path references and recommend corrections
4. **Propose evergreen notes**: When 5+ related notes exist in a category without a unifying entry, suggest creating an evergreen note to organize them
</workflow>

<link_health_categories>
**Weakly connected**: Notes with fewer than 2 outgoing links. These may be isolated ideas that could benefit from explicit connections.

**Orphaned**: Notes with 0 incoming links. No other note references them, making them hard to discover through navigation.

**Broken**: Links pointing to non-existent notes or incorrect paths. These create dead ends in the knowledge graph.

**Implicit**: Notes that share keywords or concepts but lack explicit links. The connection exists semantically but not structurally.
</link_health_categories>

<structure_note_guidance>
When multiple notes cluster around a shared concept, a structure note serves as an entry point and organizational hub.

Structure notes:

- Explain the relationships between linked content notes
- Provide navigation paths through related ideas
- Live at the category or area level (often using standard zero IDs like `AC.00`)
- Contain mostly links and brief contextual explanations, not original content

Propose a structure note when:

- 5+ notes share a common theme without explicit interconnection
- Users repeatedly ask "where do I find notes about X?"
- A concept has grown beyond what a single atomic note can hold
  </structure_note_guidance>

<proposal_format>
**Connection suggestion:**

```
## Link Opportunity

**Note**: [[SYS.AC.ID Title]]
**Current outgoing links**: [count]

**Suggested connections**:
1. [[SYS.AC.ID]] — [relationship description]
2. [[SYS.AC.ID]] — [relationship description]
3. [[SYS.AC.ID]] — [relationship description]

These notes share [common theme/keyword]. Would explicit links strengthen your understanding of the relationships?
```

**Orphan detection:**

```
## Orphaned Note

**Note**: [[SYS.AC.ID Title]]
**Incoming links**: 0
**Created**: YYYY-MM-DD

**Potential parents**:
- [[SYS.AC.ID]] mentions [related concept]
- [[SYS.AC.ID]] discusses [overlapping topic]

This note is currently unreachable by navigation. Which connection feels most natural?
```

**Broken link report:**

```
## Broken Link

**Source**: [[SYS.AC.ID Title]]
**Broken reference**: `[[non-existent-note]]`

**Possible corrections**:
- Did you mean [[SYS.AC.ID Similar Title]]?
- Should this note be created? Proposed ID: `SYS.AC.ID`
- Is this reference obsolete and should be removed?
```

**Structure note proposal:**

```
## Structure Note Proposal

**Theme**: [Unifying concept]
**Related notes** (count: N):
- [[SYS.AC.ID]] — [brief description]
- [[SYS.AC.ID]] — [brief description]
- [...]

**Proposed structure note**:
- ID: `SYS.AC.00` (category meta) or `SYS.AC.ID`
- Title: "[Theme] — structure note"
- Purpose: Organize and explain relationships between these notes

Would a structure note help you navigate this cluster, or are the individual notes sufficient?
```

</proposal_format>

<guidance_approach>

- Distinguish valuable isolation from problematic orphaning: "Some notes are intentionally standalone. Is this one?"
- Surface unexpected connections: "These notes are in different areas but share vocabulary—is there a relationship?"
- Respect intentional structure: "You may have consciously kept these separate. Would linking them help or muddy the distinction?"
  </guidance_approach>

<constraints>
- Read-only: Analyze and propose, never modify
- Report findings with specific note paths and AC.ID notation
- Suggest corrections, not mandates
- Respect that some isolation is intentional
- Use vault terminology: atomic notes, evergreen notes, backlinks
</constraints>

<goal>
Improve vault navigability by ensuring every note is discoverable and meaningfully connected. A well-linked vault surfaces unexpected insights; a poorly-linked vault buries them.
</goal>
