# Verify vault use in an authenticated harness

Use a disposable clone and vault. Run its setup script with `--vault smoke`,
then restart Claude Code, Codex, or OpenCode. Repeat these checks for each
harness you use. Do not use a personal vault for mutation checks.

1. Start in an unrelated Git repository. Confirm that `jd-vault-research` and
   `jd-vault-journal` are discoverable and the eight local management agents are
   absent. Inspect the harness's loaded instructions and MCP status.
2. Ask: "Use jd-vault-research to find my vault index and cite the note."
   Verify that the trace contains MCP retrieval and note-reading calls. A model
   answer without tool calls does not pass.
3. Ask: "Record this setup test in today's daily note and save an agent session
   with this project's path." Verify that both writes land under `JRNL/`.
4. Ask: "Crystallize this session into a permanent AGNT rule." The agent should
   explain that promotion belongs in the owning repository and keep a candidate
   in the journal. This tests instruction following, not server permissions.
5. Start a new session in the vault repository. Ask the librarian to read the
   candidate and propose its placement. Verify that the specialist can call the
   MCP. Approve a test note and verify the write and metadata.
6. Resume from the unrelated project. Verify that session recall selects that
   project's history instead of an unrelated recent vault session.
7. Rerun setup without a vault name. Verify that the selected vault, user
   instructions, unrelated MCP registrations, and existing notes are preserved.

Record CLI versions, selected vault, loaded skill names, and relevant tool calls.
Report any blocked step separately. Passing isolated setup tests cannot prove
that a model follows the installed instructions.
