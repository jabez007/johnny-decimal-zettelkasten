---
name: jd-vault-journal
description: Capture daily-note entries, agent sessions, and candidate insights in the JRNL of a registered Johnny Decimal Obsidian vault from any project. Use for logging work, saving session context, and recording ideas for later local review.
---

# Capture in the journal

1. Read the registration and check the MCP configuration as described below.
2. For daily entries, use the registered `daily_notes_folder` to confirm that the
   destination is under `JRNL/`. If the daily-note configuration has changed,
   verify it before calling `obsidian_get_daily_note`, which can create a file.
   If it points outside `JRNL/`, create a dated capture inside `JRNL/` instead.
3. Use the daily tool's returned relative `file_path`. Append under `Log` or
   `Agent Reports` with `obsidian_insert_at_heading`; preserve the existing text.
4. For agent sessions, create `JRNL/AGNT/YYYY-MM-DD-HHMMSS.md`. Include `**Goal:**`,
   `**Project:**`, outcomes, evidence, unresolved questions, and the next step.
   Use local time and record its offset. Check for collisions rather than
   overwriting another session. Include the harness name and project path.
5. Label proposed durable insights as candidates. Link to supporting notes in
   explanatory sentences. Do not promote candidates into permanent systems from
   another project.

{{POLICY}}
