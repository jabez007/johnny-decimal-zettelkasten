#!/bin/bash

# Loads repo-specific Agent Memory context into Codex at session start.

set -euo pipefail

CONFIG_PRIMARY="$HOME/.obsidian-mcp.config.json"
CONFIG_LEGACY="$HOME/.gemini-obsidian.config.json"
CONFIG_FILE=""

if [ -f "$CONFIG_PRIMARY" ]; then
  CONFIG_FILE="$CONFIG_PRIMARY"
elif [ -f "$CONFIG_LEGACY" ]; then
  CONFIG_FILE="$CONFIG_LEGACY"
fi

emit_context() {
  local message=$1
  jq -n --arg context "$message" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $context
    }
  }'
}

if [ -z "$CONFIG_FILE" ]; then
  emit_context "Agent Memory: Configuration file not found (~/.obsidian-mcp.config.json or legacy ~/.gemini-obsidian.config.json). Context restoration was skipped."
  exit 0
fi

VAULT_PATH=$(jq -r '.vault_path' "$CONFIG_FILE" 2>/dev/null || echo "")
if [ -z "$VAULT_PATH" ] || [ "$VAULT_PATH" = "null" ] || [ ! -d "$VAULT_PATH" ]; then
  emit_context "Agent Memory: Vault path not found or invalid in $CONFIG_FILE. Context restoration was skipped."
  exit 0
fi

SOPS="## Agent Memory SOPs (JD/ZK Vault)
You are integrated with a Johnny-Decimal Zettelkasten vault for persistent memory. Always use the 'gemini-obsidian' MCP tools for vault operations when they are available so path, structure, and indexing stay consistent.

**System Boundaries:**
- The 'AGNT' system is strictly for agent configuration, coding standards, and user preferences. Do NOT store user domain facts there.
- The 'JRNL' system is a transient scratchpad and session history. Evergreen 'SYS.AC.ID' notes take precedence when they conflict with journal material.

**Golden Rules:**
1. Atomicity: One declarative claim per title.
2. Contextual Linking: No bare links. Explain why the link exists in the sentence.
3. Strict Formatting: Use ACID notation (SYS.AC.ID).

### Boot Sequence (Context Restoration)
At the start of any significant task:
1. Query procedural rules relevant to the current task, especially under the 'Agent Procedural Memory' community.
2. Review the recent activity map below. If the task continues prior work, read the relevant JRNL/AGNT log before acting. If the user says 'continue' or 'resume', assume the most recent relevant log unless they specify otherwise.

### Shutdown Sequence (Context Preservation)
Before concluding a session:
1. Log execution in 'JRNL/AGNT/YYYY-MM-DD-HHMM.md'.
2. If durable new preferences or standards were established, check for an existing AGNT rule before proposing a new one.
3. New AGNT rules must use JD ACID notation, declarative titles, required YAML core fields (entities, communities, status), and a source trail back to the originating session log.
4. Add or update daily-note staff reporting when that workflow exists in the active vault."

RECENT_LOGS=$(ls -t "$VAULT_PATH/JRNL/AGNT/"*.md 2>/dev/null | head -n 5 || true)
if [ -n "$RECENT_LOGS" ]; then
  MAP_CONTENT="### Recent Activity Map (Last 5 Sessions)
| Date/Time | Goal | Path |
| :--- | :--- | :--- |"
  while read -r log_path; do
    [ -z "$log_path" ] && continue
    LOG_NAME=$(basename "$log_path")
    GOAL=$(grep -m 1 "\\*\\*Goal:\\*\\*" "$log_path" | sed 's/\*\*Goal:\*\* //' | tr -d '\r' || true)
    if [ -z "$GOAL" ]; then
      GOAL="N/A"
    fi
    MAP_CONTENT="$MAP_CONTENT
| ${LOG_NAME%.md} | $GOAL | $log_path |"
  done <<< "$RECENT_LOGS"
  STATE_CONTEXT="$MAP_CONTENT"
else
  STATE_CONTEXT="### Recent Activity Map
No previous session logs found. This is a new session or system initialization."
fi

FULL_CONTEXT="$SOPS

$STATE_CONTEXT"

emit_context "$FULL_CONTEXT"
