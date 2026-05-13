#!/bin/bash
# compile-sessions.sh [v2.0.0]
# Gathers Gemini CLI session logs across all projects and passes them to the daily-reviewer.

# Find the project root to ensure robust paths for policies
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
AGENT_POLICY="$REPO_ROOT/.gemini/agents/daily-reviewer.md"

if [ ! -f "$AGENT_POLICY" ]; then
    echo "Error: Agent policy not found at $AGENT_POLICY"
    exit 1
fi

# Argument Parsing
DATE_REGEX='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
START_DATE=""
END_DATE=""
DAYS=""

if [[ $1 =~ $DATE_REGEX ]]; then
    START_DATE=$1
    if [[ $2 =~ $DATE_REGEX ]]; then
        END_DATE=$2
        RANGE_DESC="between $START_DATE and $END_DATE"
    else
        RANGE_DESC="since $START_DATE"
    fi
else
    DAYS=${1:-1}
    RANGE_DESC="from the last $DAYS day(s)"
fi

echo "Scanning for Gemini CLI session logs $RANGE_DESC..."

# Temporary file to store the extracted conversation
TMP_FILE=$(mktemp)

# Construct Find Command
# Note: find doesn't expand * inside a string, so we use it directly in the command.
if [[ -n $START_DATE ]]; then
    if [[ -n $END_DATE ]]; then
        # Add 1 day to END_DATE to make it inclusive of that day
        NEXT_DAY=$(date -d "$END_DATE + 1 day" +%Y-%m-%d)
        find ~/.gemini/tmp/*/chats -type f \( -name "*.jsonl" -o -name "*.json" \) -newermt "$START_DATE" ! -newermt "$NEXT_DAY" 2>/dev/null
    else
        find ~/.gemini/tmp/*/chats -type f \( -name "*.jsonl" -o -name "*.json" \) -newermt "$START_DATE" 2>/dev/null
    fi
else
    find ~/.gemini/tmp/*/chats -type f \( -name "*.jsonl" -o -name "*.json" \) -mtime -${DAYS} 2>/dev/null
fi | while read -r file; do
    [[ -z "$file" ]] && continue
    echo "Processing $file..."
    
    # Extract just the user and gemini turns to keep the context clean and concise
    jq -r 'select(.type == "user" or .type == "gemini") | "[\(.type)] \(.content | tostring)"' "$file" >> "$TMP_FILE"
    
    # Add a separator between files
    echo -e "\n---\n" >> "$TMP_FILE"
done

if [ ! -s "$TMP_FILE" ]; then
    echo "No session logs found for the specified range."
    rm -f "$TMP_FILE"
    exit 0
fi

echo "Compilation complete. Invoking the daily-reviewer agent..."

PROMPT="Review the following raw session logs $RANGE_DESC. You are acting as a procedural memory compiler. Your goal is to identify and crystallize durable knowledge into the AGNT system.

Execute these tasks with precision:

1. Signal Identification: Search the logs for 'durable signals'—repeated technical corrections, specific framework preferences (e.g., Pytest vs Vitest), architectural decisions, or stylistic mandates established by the user.
2. Synthesis & De-duplication: BEFORE creating a new note, use 'obsidian_rag_query' to check if a similar rule already exists in 'AGNT/10-Procedural_Rules/'. 
   - If a rule exists: Use 'obsidian_replace_in_note' or 'obsidian_append_note' to integrate the new nuance into the existing note.
   - If no rule exists: Proceed to crystallization.
3. Structural Placement: Assign new rules to the correct Johnny-Decimal category:
   - Area 11 (Coding/Dev): Use ID pattern 'AGNT.11.xx'.
   - Area 12 (Writing/Docs): Use ID pattern 'AGNT.12.xx'.
4. Formatting Mandate:
   - Every note MUST have a complete YAML frontmatter block (aliases, tags, entities, communities, status: crystallized).
   - Use atomic, declarative titles (e.g., 'AGNT.11.03-Use-Parameterized-Testing-For-API-Routes.md').
   - Include a 'Source' section at the bottom linking to the session date (e.g., 'Source: Session logs $RANGE_DESC').
   - Keep content concise and human-readable. Do NOT use dense symbolic dialects."

# Pipe the compiled sessions into the daily-reviewer
# Using --policy to load the agent definition and -p to pass the prompt
# Using --approval-mode yolo to ensure whitelisted tools can execute in headless mode
cat "$TMP_FILE" | gemini --policy "$AGENT_POLICY" -p "$PROMPT" --approval-mode yolo

# Clean up
rm -f "$TMP_FILE"
echo "Done."
