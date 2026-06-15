#!/bin/bash
# compile-sessions.sh [v3.0.0]
# Gathers Gemini CLI and Codex CLI session logs across all projects and passes them to a reviewer host.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
AGENT_POLICY="$REPO_ROOT/.gemini/agents/daily-reviewer.md"
HOST_CLI="${AI_MEMORY_HOST:-gemini}"

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
    RANGE_DESC="from the last $DAYS day(s)"
fi

echo "Scanning for Gemini CLI and Codex CLI session logs $RANGE_DESC..."

TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

find_logs() {
    local root=$1
    shift

    if [ ! -d "$root" ]; then
        return 0
    fi

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

extract_gemini_log() {
    local file=$1
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
    ' "$file" >> "$TMP_FILE"
}

extract_codex_log() {
    local file=$1
    jq -r '
        if .type == "response_item" and .payload.type == "message" and .payload.role == "user" then
            ([.payload.content[]? | select(.type == "input_text") | .text] | join("\n")) as $text
            | if ($text | startswith("<environment_context>")) then empty else "[user] " + $text end
        elif .type == "event_msg" and .payload.type == "agent_message" then
            "[assistant] " + (.payload.message // "")
        else
            empty
        end
    ' "$file" >> "$TMP_FILE"
}

append_separator() {
    printf '\n---\n\n' >> "$TMP_FILE"
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

if [ ! -s "$TMP_FILE" ]; then
    echo "No session logs found for the specified range."
    exit 0
fi

echo "Compilation complete. Invoking the reviewer host..."

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
   - Every note MUST have a complete YAML frontmatter block with required fields `entities`, `communities`, and `status: crystallized`.
   - Add `aliases` and `tags` only when they improve discoverability or actionable intent.
   - Use atomic, declarative titles (e.g., 'AGNT.11.03-Use-Parameterized-Testing-For-API-Routes.md').
   - Include a 'Source' section at the bottom linking to the session date (e.g., 'Source: Session logs $RANGE_DESC').
   - Keep content concise and human-readable. Do NOT use dense symbolic dialects."

if [ "$HOST_CLI" = "gemini" ]; then
    if [ ! -f "$AGENT_POLICY" ]; then
        echo "Error: Gemini policy not found at $AGENT_POLICY"
        exit 1
    fi
    cat "$TMP_FILE" | gemini --policy "$AGENT_POLICY" -p "$PROMPT" --approval-mode yolo
elif [ "$HOST_CLI" = "codex" ]; then
    CODEX_PROMPT="Use the repository's configured \`daily-reviewer\` subagent role for this task. Spawn exactly one \`daily-reviewer\` subagent, do not perform the crystallization work in the parent agent, wait for the subagent to finish, and base your final answer on that subagent's crystallization work. If the \`daily-reviewer\` subagent cannot be used, stop and report that failure instead of silently continuing with the default agent.

$PROMPT"
    cat "$TMP_FILE" | codex exec -C "$REPO_ROOT" --sandbox workspace-write --ask-for-approval never --dangerously-bypass-hook-trust "$CODEX_PROMPT"
else
    echo "Error: Unsupported AI_MEMORY_HOST '$HOST_CLI'. Use 'gemini' or 'codex'."
    exit 1
fi

echo "Done."
