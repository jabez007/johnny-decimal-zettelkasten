#!/bin/bash
# compile-sessions.sh [v4.0.0]
# Gathers agent CLI session logs across all projects and passes them to a
# reviewer host acting as a procedural memory compiler.
#
# Reads logs from every harness that is present on this machine:
#   Gemini CLI  ~/.gemini/tmp/**/chats/*.json[l]      (JSON / JSONL)
#   Codex CLI   ~/.codex/sessions/**/*.jsonl          (JSONL)
#   Claude Code ~/.claude/projects/**/*.jsonl         (JSONL)
#   OpenCode    ~/.local/share/opencode/opencode.db   (SQLite)
#
# Usage:
#   ./scripts/compile-sessions.sh [DAYS]
#   ./scripts/compile-sessions.sh START_DATE [END_DATE]
#
# The reviewer host defaults to gemini; override with AI_MEMORY_HOST:
#   AI_MEMORY_HOST=claude   ./scripts/compile-sessions.sh 7
#   AI_MEMORY_HOST=codex    ./scripts/compile-sessions.sh 2026-08-01
#   AI_MEMORY_HOST=opencode ./scripts/compile-sessions.sh

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
AGENT_POLICY="$REPO_ROOT/.gemini/agents/daily-reviewer.md"
HOST_CLI="${AI_MEMORY_HOST:-gemini}"
OPENCODE_DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"

DATE_REGEX='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
START_DATE=""
END_DATE=""
DAYS=""

if [[ ${1:-} =~ $DATE_REGEX ]]; then
    START_DATE=$1
    if [[ ${2:-} =~ $DATE_REGEX ]]; then
        END_DATE=$2
        RANGE_DESC="between $START_DATE and $END_DATE"
    else
        RANGE_DESC="since $START_DATE"
    fi
else
    DAYS=${1:-1}
    if ! [[ $DAYS =~ ^[0-9]+$ ]]; then
        echo "Error: expected a day count or a YYYY-MM-DD date, got '$DAYS'."
        exit 1
    fi
    RANGE_DESC="from the last $DAYS day(s)"
fi

# Epoch-millisecond bounds for the SQLite-backed host.
if [[ -n $START_DATE ]]; then
    START_MS=$(( $(date -d "$START_DATE" +%s) * 1000 ))
    if [[ -n $END_DATE ]]; then
        END_MS=$(( $(date -d "$END_DATE + 1 day" +%s) * 1000 ))
    else
        END_MS=$(( $(date +%s) * 1000 ))
    fi
else
    START_MS=$(( $(date -d "$DAYS days ago" +%s) * 1000 ))
    END_MS=$(( $(date +%s) * 1000 ))
fi

echo "Scanning for agent CLI session logs $RANGE_DESC..."

TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

find_logs() {
    local root=$1
    shift

    [ -d "$root" ] || return 0

    if [[ -n $START_DATE ]]; then
        if [[ -n $END_DATE ]]; then
            local next_day
            next_day=$(date -d "$END_DATE + 1 day" +%Y-%m-%d)
            find "$root" -type f "$@" -newermt "$START_DATE" ! -newermt "$next_day" 2>/dev/null
        else
            find "$root" -type f "$@" -newermt "$START_DATE" 2>/dev/null
        fi
    else
        find "$root" -type f "$@" -mtime -"$DAYS" 2>/dev/null
    fi
}

append_separator() {
    printf '\n---\n\n' >>"$TMP_FILE"
}

extract_gemini_log() {
    jq -r '
        def render_text:
            if .message? then
                .message
            elif (.content? | type) == "string" then
                .content
            elif (.content? | type) == "array" then
                [.content[]? | .text // tostring] | join("\n")
            else
                ""
            end;

        (if type == "array" then .[] else . end)
        | select(.type == "user" or .type == "gemini")
        | . as $entry
        | render_text as $text
        | select($entry.type == "user" or $text != "")
        | "[\($entry.type)] \($text)"
    ' "$1" >>"$TMP_FILE"
}

extract_codex_log() {
    jq -r '
        if .type == "response_item" and .payload.type == "message" and .payload.role == "user" then
            ([.payload.content[]? | select(.type == "input_text") | .text] | join("\n")) as $text
            | if ($text | startswith("<environment_context>")) then empty else "[user] " + $text end
        elif .type == "event_msg" and .payload.type == "agent_message" then
            "[assistant] " + (.payload.message // "")
        else
            empty
        end
    ' "$1" >>"$TMP_FILE"
}

extract_claude_log() {
    # Real user turns carry a plain string content; an array content is a
    # tool_result echo, which is noise for procedural-memory mining.
    jq -r '
        if .type == "user" and (.message.content | type) == "string" then
            "[user] " + .message.content
        elif .type == "assistant" and (.message.content | type) == "array" then
            ([.message.content[]? | select(.type == "text") | .text] | join("\n")) as $text
            | if ($text | length) == 0 then empty else "[assistant] " + $text end
        else
            empty
        end
    ' "$1" >>"$TMP_FILE"
}

extract_opencode_logs() {
    # OpenCode keeps sessions in SQLite: message rows hold the role, part rows
    # hold the text, both as JSON in a `data` column.
    if [ ! -f "$OPENCODE_DB" ]; then
        return 0
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "Note: sqlite3 not installed; skipping OpenCode logs." >&2
        return 0
    fi

    echo "Processing OpenCode database $OPENCODE_DB..."
    sqlite3 -noheader -separator '' "$OPENCODE_DB" "
        SELECT '[' || json_extract(m.data, '\$.role') || '] '
               || json_extract(p.data, '\$.text') || char(10)
        FROM message m
        JOIN part p ON p.message_id = m.id
        WHERE json_extract(p.data, '\$.type') = 'text'
          AND json_extract(p.data, '\$.text') IS NOT NULL
          AND m.time_created >= $START_MS
          AND m.time_created < $END_MS
        ORDER BY m.time_created, p.time_created;
    " >>"$TMP_FILE" 2>/dev/null || echo "Note: could not read OpenCode database." >&2
    append_separator
}

while read -r file; do
    [ -z "$file" ] && continue
    echo "Processing Gemini log $file..."
    extract_gemini_log "$file"
    append_separator
done < <(find_logs "$HOME/.gemini/tmp" \( -path '*/chats/*' \) \( -name "*.jsonl" -o -name "*.json" \))

while read -r file; do
    [ -z "$file" ] && continue
    echo "Processing Codex log $file..."
    extract_codex_log "$file"
    append_separator
done < <(find_logs "$HOME/.codex/sessions" -name "*.jsonl")

while read -r file; do
    [ -z "$file" ] && continue
    echo "Processing Claude Code log $file..."
    extract_claude_log "$file"
    append_separator
done < <(find_logs "$HOME/.claude/projects" -name "*.jsonl")

extract_opencode_logs

if [ ! -s "$TMP_FILE" ]; then
    echo "No session logs found for the specified range."
    exit 0
fi

if [ -n "${AI_MEMORY_DRY_RUN:-}" ]; then
    echo "Dry run: compiled $(wc -l <"$TMP_FILE") lines, $(wc -c <"$TMP_FILE") bytes."
    if [ "$AI_MEMORY_DRY_RUN" = "dump" ]; then
        cat "$TMP_FILE"
    fi
    exit 0
fi

echo "Compilation complete. Invoking the reviewer host ($HOST_CLI)..."

PROMPT="Review the following raw session logs $RANGE_DESC. You are acting as a procedural memory compiler. Your goal is to identify and crystallize durable knowledge into the AGNT system.

Execute these tasks with precision:

1. Signal Identification: Search the logs for 'durable signals'—repeated technical corrections, specific framework preferences (e.g., Pytest vs Vitest), architectural decisions, or stylistic mandates established by the user.
2. Synthesis & De-duplication: BEFORE creating a new note, use the available Obsidian MCP tools to check whether a similar rule already exists in 'AGNT/10-Procedural_Rules/'.
   - If a rule exists: integrate the new nuance into the existing note instead of duplicating it.
   - If no rule exists: Proceed to crystallization.
3. Structural Placement: Assign new rules to the correct Johnny-Decimal category:
   - Area 11 (Coding/Dev): Use ID pattern 'AGNT.11.xx'.
   - Area 12 (Writing/Docs): Use ID pattern 'AGNT.12.xx'.
4. Formatting Mandate:
   - Every note MUST have a complete YAML frontmatter block with required fields \`entities\`, \`communities\`, and \`status: crystallized\`.
   - Add \`aliases\` and \`tags\` only when they improve discoverability or actionable intent.
   - Use atomic, declarative titles (e.g., 'AGNT.11.03-Use-Parameterized-Testing-For-API-Routes.md').
   - Include a 'Source' section at the bottom linking to the session date (e.g., 'Source: Session logs $RANGE_DESC').
   - Keep content concise and human-readable. Do NOT use dense symbolic dialects.
5. Note that 'obsidian_create_note' refuses to overwrite an existing note. If it refuses, treat that as an ID collision: pick the next free ID or update the existing rule instead of forcing 'overwrite'."

DELEGATE_PREFIX="Use the repository's configured \`daily-reviewer\` subagent for this task. Spawn exactly one \`daily-reviewer\` subagent, do not perform the crystallization work in the parent agent, wait for the subagent to finish, and base your final answer on that subagent's crystallization work. If the \`daily-reviewer\` subagent cannot be used, stop and report that failure instead of silently continuing with the default agent."

case "$HOST_CLI" in
    gemini)
        if [ ! -f "$AGENT_POLICY" ]; then
            echo "Error: Gemini policy not found at $AGENT_POLICY"
            exit 1
        fi
        gemini --policy "$AGENT_POLICY" -p "$PROMPT" --approval-mode yolo <"$TMP_FILE"
        ;;
    codex)
        codex exec -C "$REPO_ROOT" --sandbox workspace-write --ask-for-approval never \
            --dangerously-bypass-hook-trust "$DELEGATE_PREFIX

$PROMPT" <"$TMP_FILE"
        ;;
    claude)
        claude -p "$DELEGATE_PREFIX

$PROMPT" --permission-mode acceptEdits --add-dir "$REPO_ROOT" <"$TMP_FILE"
        ;;
    opencode)
        opencode run --agent daily-reviewer --dir "$REPO_ROOT" "$PROMPT

--- SESSION LOGS ---
$(cat "$TMP_FILE")"
        ;;
    *)
        echo "Error: Unsupported AI_MEMORY_HOST '$HOST_CLI'. Use gemini, codex, claude, or opencode."
        exit 1
        ;;
esac

echo "Done."
