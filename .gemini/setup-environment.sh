#!/bin/bash

# setup-environment.sh
# Configures the gemini-obsidian extension for the Librarian project.

set -e

echo "--- 1. Installing gemini-obsidian extension globally ---"
# This allows the Gemini CLI to discover the extension's code.
if ! gemini extension list 2>&1 | grep -q "gemini-obsidian"; then
  gemini extensions install https://github.com/jabez007/gemini-obsidian --consent
else
  echo "Extension gemini-obsidian is already installed. Skipping installation."
fi

echo "--- 2. Building extension & Installing native dependencies ---"
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

echo "--- 3. Configuring Vault via Extension CLI ---"
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

echo "--- 4. Configuring Git LFS for binary files ---"
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

echo "--- 5. Hooking Global Gemini CLI ---"
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
  echo "{}"
  exit 0
fi

# Use jq to read config safely
VAULT_PATH=$(jq -r '.vault_path' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$VAULT_PATH" ] || [ "$VAULT_PATH" == "null" ] || [ ! -d "$VAULT_PATH" ]; then
  echo "{}"
  exit 0
fi

# 1. SOPs (The "How-To")
SOPS="## Agent Memory SOPs (JD/ZK Vault)
You are integrated with a Johnny-Decimal Zettelkasten vault for persistent memory. Always use the 'gemini-obsidian' MCP tools for vault operations to ensure path and structural integrity.

### Boot Sequence (Context Restoration)
At the start of any significant task:
1.  **Query Rules:** Run 'obsidian_rag_query' searching for the current task's entities within the 'communities: [Agent Procedural Memory]' cluster.
2.  **Restore State:** Review the 'Last Session Log' provided in the initial context. Use 'obsidian_read_note' if you need to explore related notes mentioned in that log.

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

# 2. Last Log (The "State")
# Find the latest log in the episodic journal
LAST_LOG_FILE=$(ls -t "$VAULT_PATH/JRNL/AGNT/"*.md 2>/dev/null | head -n 1)
if [ -f "$LAST_LOG_FILE" ]; then
  LOG_CONTENT=$(cat "$LAST_LOG_FILE")
  STATE_CONTEXT="### Last Session Log ($LAST_LOG_FILE)
$LOG_CONTENT"
else
  STATE_CONTEXT="### Last Session Log
No previous logs found. This is a new session or system initialization."
fi

# Final Context
FULL_CONTEXT="$SOPS

$STATE_CONTEXT"

# Output as JSON
jq -n --arg context "$FULL_CONTEXT" '{"hookSpecificOutput": {"additionalContext": $context}}'
EOF

chmod +x "$HOOK_SCRIPT"

echo "Updating global settings.json at $GLOBAL_SETTINGS_JSON..."
if [ ! -f "$GLOBAL_SETTINGS_JSON" ]; then
  echo '{"hooks": {"SessionStart": []}}' >"$GLOBAL_SETTINGS_JSON"
fi

# Add the hook to settings.json if it's not already there
# We use jq to safely merge the hook into the SessionStart list.
TEMP_SETTINGS=$(mktemp)
jq --arg name "agent-memory-boot" \
  --arg script "$HOOK_SCRIPT" \
  '(.hooks.SessionStart // []) |= (if map(.name == $name) | any then . else . + [{"name": $name, "type": "command", "command": $script}] end)' \
  "$GLOBAL_SETTINGS_JSON" >"$TEMP_SETTINGS" && mv "$TEMP_SETTINGS" "$GLOBAL_SETTINGS_JSON"

echo "--- 6. Finalizing Environment ---"
# Confirm that the Librarian skill and Obsidian extension are ready.
echo "Active Skills in this Workspace:"
gemini skills list

echo "Active Extensions in this Workspace:"
gemini extensions list

echo "-------------------------------------------------------"
echo "Setup Complete! The gemini-obsidian extension is now"
echo "active only within this project's workspace."
echo "-------------------------------------------------------"
