---
agent: librarian
---

<purpose>
Generate spaced repetition flashcards for a single note. Review the document's content, identify key concepts without existing questions, and append new flashcards to a `# Questions` section.
</purpose>

<invocation>
```
/flashcards Generate for #somefile.md
```
</invocation>

<workflow>
1. **Read the target file**: Parse the entire note content
2. **Identify the Questions section**: Look for existing `# Questions` heading
3. **Analyze existing cards**: Note which topics/concepts already have questions to avoid duplication
4. **Identify key concepts**: Extract claims, definitions, relationships, and facts from the note body
5. **Generate new cards**: Create flashcards for uncovered concepts using approved formats only
6. **Suggest Incorporation**: Suggest obsidian footnotes to insert new cards and reference the information source in the note
</workflow>

<card_formats>
Only two formats are permitted. Do not use any other patterns.

**Simple Q&A** — Use for direct factual questions:

```
Question text here::Answer text here
```

Example:

```
What is the maximum number of areas per system in Johnny Decimal?::16 (hex digits 1-F, with 0 reserved for meta)
```

**Simplified Cloze** — Use for fill-in-the-blank recall with optional hints:

Without hint:

```
The first female prime minister of Australia was ==Julia Gillard==
```

With hint (use `^[hint text]` immediately after the cloze):

```
This ==note==^[type of document] doesn't need to have ==numbers==^[sequencing] on clozes
```

Multiple clozes in one statement generate multiple cards:

```
Johnny Decimal uses ==Areas== for broad groupings and ==Categories== for subdivisions
```

</card_formats>

<card_generation_guidelines>
**Prefer clozes when**:

- The answer is embedded in a meaningful sentence
- Context aids recall
- Testing recognition of terms within statements

**Prefer Q&A when**:

- The question requires explanation
- Multiple valid phrasings exist for the answer
- Testing recall of standalone facts

**Quality principles**:

- One atomic concept per card
- Clear, unambiguous questions
- Answers should be concise (1-2 sentences max)
- Use hints sparingly—only when the cloze would be too difficult without context
- Avoid yes/no questions; prefer "what", "how", "why"
- Draw from the note's actual claims, not external knowledge
  </card_generation_guidelines>

<example_output>
For a note about ACID notation:

```markdown
# Questions

What does ACID stand for in Johnny Decimal notation?::Area, Category, ID

The format for ACID notation is ==SYS.AC.ID==^[three-part structure]

In ACID notation, ==SYS== is a 2-4 letter system code

The maximum number of IDs per category is ==256==^[hex 00-FF]

Why are standard zeros reserved in Johnny Decimal?::To hold meta-information about the containing level (system, area, or category)
```

</example_output>

<constraints>
- **Read only**: Never delete or modify existing content in the note
- **Single file**: Operates on exactly one file per invocation
- **Two formats only**: Use only `Q::A` and simplified clozes (`==answer==` with optional `^[hint]`)
- **No other card patterns**: Do not use classic clozes, generalized overlapping, or custom patterns
- **No duplication**: Skip concepts that already have questions in the existing `# Questions` section
- **Source fidelity**: Generate cards only from content present in the note
- **Suggest Footnotes**: Recommendations should be made to add obsidian footnotes linking to the source of each answer within the note
</constraints>

<guidance_approach>
After generating cards, ask:

```
I've come up with [N] flashcards covering:
- [Topic 1]
- [Topic 2]
- [...]

Are there specific concepts you'd like more cards for, or any cards that should be revised?
```

</guidance_approach>

<goal>
Transform note content into durable memory through spaced repetition. Each card should test a single concept that matters for understanding the note's core claims.
</goal>
