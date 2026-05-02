#!/bin/bash

# setup-environment.sh
# Configures the gemini-obsidian extension for the Librarian project.

set -e

echo "--- 1. Dependency Checks ---"
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: 'jq' is not installed. Please install it to continue."
  echo "On Ubuntu/Debian: sudo apt-get install jq"
  echo "On macOS: brew install jq"
  exit 1
fi
echo "'jq' found."

echo "--- 2. Installing gemini-obsidian extension globally ---"
# This allows the Gemini CLI to discover the extension's code.
if ! gemini extension list 2>&1 | grep -q "gemini-obsidian"; then
  gemini extensions install https://github.com/jabez007/gemini-obsidian --consent
else
  echo "Extension gemini-obsidian is already installed. Skipping installation."
fi

echo "--- 3. Building extension & Installing native dependencies ---"
# Since this extension uses LanceDB/ONNX, we must ensure binaries are built.
# We target the global installation directory.
# We capture the output and strip everything before the first '[' to ensure jq gets valid JSON.
# Using 2>&1 to capture output because the CLI writes list output to stderr.
RAW_LIST=$(gemini extensions list -o json 2>&1)
EXT_PATH=$(echo "$RAW_LIST" | sed -n '/\[/,$p' | jq -r '.[] | select(.name=="gemini-obsidian") | .path' 2>/dev/null || echo "")

# Fallback: If jq fails or path is empty, try to find it in the default local user directory
if [ -z "$EXT_PATH" ] || [ "$EXT_PATH" == "null" ]; then
  echo "Direct JSON lookup failed (found: '$EXT_PATH'), searching default extension directory..."
  EXT_PATH="$HOME/.gemini/extensions/gemini-obsidian"
fi

if [ ! -d "$EXT_PATH" ]; then
  echo "Error: Extension directory not found at $EXT_PATH."
  exit 1
fi

echo "Extension found at: $EXT_PATH"

pushd "$EXT_PATH" >/dev/null
echo "Running npm install..."
npm install --quiet
echo "Running npm build..."
npm run build --quiet
popd >/dev/null

echo "--- 4. Configuring Vault via Extension CLI ---"
# Prompt for vault name
VAULT_NAME_RAW=""
if [ -t 0 ]; then
  read -rp "Enter Obsidian vault name [example]: " VAULT_NAME_RAW
fi

if [ -z "$VAULT_NAME_RAW" ]; then
  VAULT_NAME_RAW="example"
fi

# Slugify: lowercase, replace non-alphanumeric with hyphens, collapse hyphens, trim ends
VAULT_SLUG=$(echo "$VAULT_NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{1,\}/-/g' | sed 's/^-//;s/-$//')

WORKSPACE_DIR="$(pwd)"
VAULT_PATH="$WORKSPACE_DIR/vaults/$VAULT_SLUG"

if [ ! -d "$VAULT_PATH" ]; then
  echo "Creating new vault directory at $VAULT_PATH..."
  mkdir -p "$VAULT_PATH"
else
  echo "Using existing vault directory at $VAULT_PATH."
fi

# Derive vault_id from project directory and vault slug
PWD_BASE=$(basename "$WORKSPACE_DIR")
VAULT_ID="${PWD_BASE}_${VAULT_SLUG}"

# We use the extension's own tool to ensure the config file is correctly formatted.
# This sets vault_path, workspace_path, and vault_id in ~/.gemini-obsidian.config.json
node "$EXT_PATH/dist/index.js" obsidian_set_vault \
  --path "$VAULT_PATH" \
  --workspace_path "$WORKSPACE_DIR" \
  --vault_id "$VAULT_ID"

# Prompt for initial indexing
if [ -t 0 ]; then
  read -rp "Would you like to perform initial semantic indexing now? (y/n) [n]: " DO_INDEX
  if [[ "$DO_INDEX" =~ ^[Yy]$ ]]; then
    echo "Starting semantic indexing (this may take a few minutes)..."
    node "$EXT_PATH/dist/index.js" obsidian_rag_index \
      --path "$VAULT_PATH" \
      --workspace_path "$WORKSPACE_DIR" \
      --vault_id "$VAULT_ID"
  fi
fi

echo "--- 5. Configuring Git LFS for binary files ---"
# Since LanceDB datasets contain binary files, Git LFS should be used to store them efficiently.
# Check if git is available before running.
if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
  if command -v git-lfs >/dev/null 2>&1; then
    echo "Initializing Git LFS..."
    git lfs install --local
    git lfs track ".gemini-obsidian/**/*.lance"
    git lfs track ".gemini-obsidian/**/*.lance/**"
    git lfs track ".gemini-obsidian/**/*.onnx"
  else
    echo "Warning: git-lfs not found. Binary files will not be tracked efficiently."
  fi
else
  echo "Skipping Git LFS setup (not a git repository or git not found)."
fi

echo "--- 6. Hooking Global Gemini CLI ---"
# This configures a global SessionStart hook to inject Agent Memory SOPs and state.
GLOBAL_GEMINI_DIR="$HOME/.gemini"
GLOBAL_HOOKS_DIR="$GLOBAL_GEMINI_DIR/hooks"
GLOBAL_SETTINGS_JSON="$GLOBAL_GEMINI_DIR/settings.json"
HOOK_SCRIPT="$GLOBAL_HOOKS_DIR/agent-memory-boot.sh"

mkdir -p "$GLOBAL_HOOKS_DIR"

echo "Creating global hook script at $HOOK_SCRIPT..."
cat >"$HOOK_SCRIPT" <<'EOF'
#!/bin/bash
# Hook: SessionStart
# Injects Agent Memory SOPs and Restores Session State

CONFIG_FILE="$HOME/.gemini-obsidian.config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  jq -n '{"systemMessage": "Agent Memory: Configuration file not found (~/.gemini-obsidian.config.json). SOPs and activity map were not loaded."}'
  exit 0
fi

# Use jq to read config safely
VAULT_PATH=$(jq -r '.vault_path' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$VAULT_PATH" ] || [ "$VAULT_PATH" == "null" ] || [ ! -d "$VAULT_PATH" ]; then
  jq -n '{"systemMessage": "Agent Memory: Vault path not found or invalid. SOPs and activity map were not loaded."}'
  exit 0
fi

# 1. SOPs (The "How-To")
SOPS="## Agent Memory SOPs (JD/ZK Vault)
You are integrated with a Johnny-Decimal Zettelkasten vault for persistent memory. Always use the 'gemini-obsidian' MCP tools for vault operations to ensure path and structural integrity.

**System Boundaries:**
- The 'AGNT' system is strictly for agent configuration and preferences. Do NOT store facts about the world or the user's personal domains here.
- The 'JRNL' system is a transient scratchpad. Evergreen 'SYS.AC.ID' notes always take precedence in RAG queries.

**Golden Rules:**
1. Atomicity: One declarative claim per title.
2. Contextual Linking: No bare links. Explain why the link exists in the sentence.
3. Strict Formatting: Use ACID notation (SYS.AC.ID).

### Boot Sequence (Context Restoration)
At the start of any significant task:
1.  **Query Rules:** Run 'obsidian_rag_query' searching for the current task's entities within the 'communities: [Agent Procedural Memory]' cluster.
2.  **Select Context:** Review the 'Recent Activity Map' provided below. If your current task relates to a previous session, use 'obsidian_read_note' to fetch that specific log's full content before proceeding. If the user explicitly says 'continue' or 'resume', assume the most recent log.

### Shutdown Sequence (Context Preservation)
Before concluding a session:
1.  **Log Execution:** Use 'obsidian_create_note' to write a summary of the session to 'JRNL/AGNT/YYYY-MM-DD-HHMM.md'.
2.  **Crystallize Rules:** If new preferences or technical standards were established:
    - Search for existing rules using 'obsidian_search_notes'.
    - Propose a new atomic note in the appropriate category folder under 'AGNT/10-Procedural_Rules/' (e.g., '11-Coding/' or '12-Writing/').
    - **Naming Convention:** The filename MUST follow the 'SYS.AC.ID-Title.md' format (e.g., 'AGNT.11.05-Declarative-Title.md').
    - **Hexadecimal Standard:** Use hexadecimal (**0-F**) for all numbering. Areas and Categories use 1-F (0 is reserved for indices). IDs use **01-FF**.
    - **Metadata:** Include the mandatory YAML block (entities, communities: [Agent Procedural Memory], status: crystallized).
    - **Header:** The first line of the note (after YAML) MUST be a link to the system index: '[[AGNT.00.00]]'.
    - **Body:** Link back to the source log in 'JRNL/AGNT/' for traceability.
    - **Indexing:** If a new rule is created, run 'obsidian_rag_index' for that specific file to ensure immediate discoverability.
3.  **Transparency (Staff Report):** 
    - Use 'obsidian_get_daily_note' to find today's note.
    - Use 'obsidian_insert_at_heading' to append a brief 'Staff Report' (including an embed of your new log) under the '## Log' or '## Agent Reports' heading."

# 2. Recent Activity Map
# Find the last 5 logs to provide a navigation map
RECENT_LOGS=$(ls -t "$VAULT_PATH/JRNL/AGNT/"*.md 2>/dev/null | head -n 5)
if [ -n "$RECENT_LOGS" ]; then
  MAP_CONTENT="### Recent Activity Map (Last 5 Sessions)
| Date/Time | Goal | Path |
| :--- | :--- | :--- |"
  while read -r log_path; do
    LOG_NAME=$(basename "$log_path")
    # Extract Goal line, stripping markdown formatting
    GOAL=$(grep -m 1 "**Goal:**" "$log_path" | sed 's/\*\*Goal:\*\* //' | tr -d '\r')
    if [ -z "$GOAL" ]; then GOAL="N/A"; fi
    MAP_CONTENT="$MAP_CONTENT
| ${LOG_NAME%.md} | $GOAL | $log_path |"
  done <<< "$RECENT_LOGS"
  STATE_CONTEXT="$MAP_CONTENT"
else
  STATE_CONTEXT="### Recent Activity Map
No previous session logs found. This is a new session or system initialization."
fi

# Final Context
FULL_CONTEXT="$SOPS

$STATE_CONTEXT"

# Output as JSON
jq -n --arg context "$FULL_CONTEXT" \
      --arg msg "Agent Memory: SOPs and Activity Map successfully restored from $VAULT_PATH." \
      '{"systemMessage": $msg, "hookSpecificOutput": {"additionalContext": $context}}'
EOF

chmod +x "$HOOK_SCRIPT"

echo "Updating global settings.json at $GLOBAL_SETTINGS_JSON..."
if [ ! -f "$GLOBAL_SETTINGS_JSON" ]; then
  echo '{}' >"$GLOBAL_SETTINGS_JSON"
fi

# Add the hook to settings.json if it's not already there
# We use jq to safely merge the hook into the SessionStart list.
TEMP_SETTINGS=$(mktemp)
jq --arg name "agent-memory-boot" \
  --arg script "$HOOK_SCRIPT" \
  '.hooks |= (. // {}) | 
   .hooks.SessionStart |= (. // []) |
   if any(.hooks.SessionStart[]; .hooks? // [] | any(.[]; .name == $name)) then
     .
   else
     .hooks.SessionStart += [{"matcher": "*", "hooks": [{"name": $name, "type": "command", "command": $script}]}]
   end' \
  "$GLOBAL_SETTINGS_JSON" >"$TEMP_SETTINGS" && mv "$TEMP_SETTINGS" "$GLOBAL_SETTINGS_JSON"

echo "--- 7. Finalizing Environment ---"
# Confirm that the Librarian skill and Obsidian extension are ready.
echo "Active Skills in this Workspace:"
gemini skills list

echo "Active Extensions in this Workspace:"
gemini extensions list

echo "-------------------------------------------------------"
echo "Setup Complete! The gemini-obsidian extension is now"
echo "active only within this project's workspace."
echo "-------------------------------------------------------"
