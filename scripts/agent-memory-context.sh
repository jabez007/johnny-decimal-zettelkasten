#!/bin/bash

# agent-memory-context.sh
# Canonical Agent Memory boot context, shared by every harness SessionStart hook.
#
# Prints the SOPs and a Recent Activity Map as plain text on stdout. Each
# harness hook wraps this output in whatever JSON shape it expects, so the
# instructions themselves live in exactly one place.
#
# Exits 0 with a short diagnostic on stdout when no vault is configured, so a
# missing vault degrades to a notice instead of failing the session start.

set -euo pipefail

CONFIG_PRIMARY="$HOME/.obsidian-mcp.config.json"
# v2 writes only to the primary path but still reads this legacy name.
CONFIG_LEGACY="$HOME/.gemini-obsidian.config.json"
CONFIG_FILE=""

if [ -f "$CONFIG_PRIMARY" ]; then
  CONFIG_FILE="$CONFIG_PRIMARY"
elif [ -f "$CONFIG_LEGACY" ]; then
  CONFIG_FILE="$CONFIG_LEGACY"
fi

if [ -z "$CONFIG_FILE" ]; then
  echo "Agent Memory: no vault configured (~/.obsidian-mcp.config.json not found). Context restoration skipped."
  exit 0
fi

VAULT_PATH=$(jq -r '.vault_path // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  echo "Agent Memory: vault path missing or invalid in $CONFIG_FILE. Context restoration skipped."
  exit 0
fi

cat <<'SOPS'
## Agent Memory SOPs (JD/ZK Vault)

You are integrated with a Johnny-Decimal Zettelkasten vault that serves as your
persistent memory. Use the `obsidian-vault-mcp` MCP tools for all vault
operations so path handling, structure, and indexing stay consistent.

**System Boundaries:**
- `AGNT` is strictly for agent procedural memory: coding standards, tooling
  preferences, and behavioral rules. Never store facts about the world or the
  user's personal domains there.
- `JRNL` is a transient scratchpad and session history. When a JRNL note
  conflicts with an evergreen `SYS.AC.ID` note, the evergreen note wins.

**Golden Rules:**
1. Atomicity: one declarative claim per title.
2. Contextual linking: no bare link dumps. Explain why each link exists in the
   sentence that carries it.
3. Strict formatting: ACID notation (`SYS.AC.ID`), hexadecimal throughout.

### Boot Sequence (Context Restoration)
At the start of any significant task:
1. Query procedural rules with `obsidian_rag_query`, searching the current
   task's entities within the `Agent Procedural Memory` community.
2. Review the Recent Activity Map below. If the task continues earlier work,
   read that session's log with `obsidian_read_note` before acting. If the user
   says "continue" or "resume", assume the most recent log unless told otherwise.

### Shutdown Sequence (Context Preservation)
Before concluding a session:
1. Log the session to `JRNL/AGNT/YYYY-MM-DD-HHMM.md` via `obsidian_create_note`.
   Include a `**Goal:**` line — the Recent Activity Map is built from it.
2. If durable new preferences or standards were established, search for an
   existing rule with `obsidian_search_notes` before proposing a new one.
   Prefer updating an existing rule over adding a near-duplicate.
3. New AGNT rules go in `AGNT/10-Procedural_Rules/<area>/` and must use:
   - Filename `SYS.AC.ID-Declarative-Title.md` (e.g. `AGNT.11.05-...`).
   - Hexadecimal numbering: areas and categories `1-F` (`0` is reserved for
     indexes), IDs `01-FF`.
   - YAML frontmatter with required core fields `entities`, `communities`
     (including `Agent Procedural Memory`), and `status: crystallized`.
   - `[[AGNT.00.00]]` as the first line after the frontmatter.
   - A link back to the originating `JRNL/AGNT/` log for traceability.
4. Note-writing MCP tools re-index the changed note inside the server, so no
   manual re-index step is needed after a write.
5. If the active vault uses daily-note staff reporting, append a brief report
   under the daily note's `## Log` or `## Agent Reports` heading using
   `obsidian_get_daily_note` and `obsidian_insert_at_heading`.
SOPS

echo ""

# Extract a session log's goal. Two formats exist in the wild:
#   **Goal:** <text>          - inline, used by the example vault
#   ## Goal\n<text>           - heading, with the goal on the following line
extract_goal() {
  awk '
    # Inline form wins if present.
    /\*\*Goal:\*\*/ {
      line = $0
      sub(/.*\*\*Goal:\*\*[[:space:]]*/, "", line)
      gsub(/\r/, "", line)
      if (line != "") { print line; exit }
    }
    # Heading form: capture the first non-empty line after the heading.
    /^#+[[:space:]]*Goal[[:space:]]*:?[[:space:]]*$/ { want = 1; next }
    want && NF {
      gsub(/\r/, "", $0)
      print
      exit
    }
  ' "$1" 2>/dev/null | head -n 1
}

# Recent Activity Map: the last 5 session logs and what each one set out to do.
RECENT_LOGS=$(ls -t "$VAULT_PATH/JRNL/AGNT/"*.md 2>/dev/null | head -n 5 || true)
if [ -n "$RECENT_LOGS" ]; then
  echo "### Recent Activity Map (Last 5 Sessions)"
  echo "| Date/Time | Goal | Path |"
  echo "| :--- | :--- | :--- |"
  while read -r log_path; do
    [ -z "$log_path" ] && continue
    log_name=$(basename "$log_path")
    goal=$(extract_goal "$log_path")
    # Keep the table readable and never let a stray pipe break the row.
    goal=${goal//|/\\|}
    [ -z "$goal" ] && goal="N/A"
    echo "| ${log_name%.md} | $goal | $log_path |"
  done <<<"$RECENT_LOGS"
else
  echo "### Recent Activity Map"
  echo "No previous session logs found. This is a new session or a fresh vault."
fi
