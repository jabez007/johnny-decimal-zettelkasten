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

echo "--- 3. Configuring Vault ---"
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

# Johnny-Decimal Defaults & Interactive Prompts
# We provide sensible defaults but allow user customization via interactive prompts.
KNOWLEDGE_FOLDERS_JSON='["LIFE"]'
MOC_FOLDERS_JSON='["_SYS", "00-IDX"]'
DAILY_NOTE_FOLDER='JRNL'
IGNORED_FOLDERS_JSON='[".obsidian", ".trash"]'

if [ -t 0 ]; then
  echo "Configure your Johnny-Decimal structure (press Enter for defaults):"

  read -rp "Enter Knowledge folders (comma-separated) [LIFE]: " KNOWLEDGE_INPUT
  if [ ! -z "$KNOWLEDGE_INPUT" ]; then
    KNOWLEDGE_FOLDERS_JSON=$(echo "$KNOWLEDGE_INPUT" | jq -Rc 'split(",") | map(gsub("^ +| +$"; ""))')
  fi

  read -rp "Enter MOC folders (comma-separated) [_SYS, 00-IDX]: " MOC_INPUT
  if [ ! -z "$MOC_INPUT" ]; then
    # Merge user input with the required "_SYS" and "00-IDX" folders, trim whitespace, and unique-ify the array
    MOC_FOLDERS_JSON=$(echo "$MOC_INPUT" | jq -Rc 'split(",") | . + ["_SYS", "00-IDX"] | map(gsub("^ +| +$"; "")) | unique')
  else
    MOC_FOLDERS_JSON='["_SYS", "00-IDX"]'
  fi

  read -rp "Enter Daily Note folder [JRNL]: " DAILY_INPUT
  [ ! -z "$DAILY_INPUT" ] && DAILY_NOTE_FOLDER=$DAILY_INPUT

  read -rp "Enter Ignored folders (comma-separated) [.obsidian, .trash]: " IGNORED_INPUT
  if [ ! -z "$IGNORED_INPUT" ]; then
    IGNORED_FOLDERS_JSON=$(echo "$IGNORED_INPUT" | jq -Rc 'split(",") | map(gsub("^ +| +$"; ""))')
  fi
fi

# Set configuration in the global config.
# We use $HOME instead of ~ for better script portability and to allow for safe quoting.
CONFIG_FILE="$HOME/.gemini-obsidian.config.json"

if command -v jq >/dev/null 2>&1; then
  echo "Updating $CONFIG_FILE with workspace_path, vault_path, and user-defined Johnny-Decimal folders..."
  # Create config if it doesn't exist
  if [ ! -f "$CONFIG_FILE" ]; then echo "{}" >"$CONFIG_FILE"; fi

  jq --arg wp "$WORKSPACE_DIR" \
    --arg vp "$VAULT_PATH" \
    --arg vid "$VAULT_ID" \
    --argjson kf "$KNOWLEDGE_FOLDERS_JSON" \
    --argjson mf "$MOC_FOLDERS_JSON" \
    --arg dnf "$DAILY_NOTE_FOLDER" \
    --argjson igf "$IGNORED_FOLDERS_JSON" \
    '.workspace_path = $wp | .vault_path = $vp | .vault_id = $vid | .knowledge_folders = $kf | .moc_folders = $mf | .daily_note_folder = $dnf | .ignored_folders = $igf' \
    "$CONFIG_FILE" >"${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
else
  if [ -f "$CONFIG_FILE" ]; then
    echo "Warning: jq not found. To avoid destroying existing settings in $CONFIG_FILE, the update was skipped."
    echo "Please manually add these values to your config file:"
    printf '  "workspace_path": "%s",\n  "vault_path": "%s",\n  "vault_id": "%s"\n' "$WORKSPACE_DIR" "$VAULT_PATH" "$VAULT_ID"
    printf '  "knowledge_folders": %s,\n  "moc_folders": %s,\n  "daily_note_folder": "%s",\n  "ignored_folders": %s\n' "$KNOWLEDGE_FOLDERS_JSON" "$MOC_FOLDERS_JSON" "$DAILY_NOTE_FOLDER" "$IGNORED_FOLDERS_JSON"
  else
    printf '{\n  "workspace_path": "%s",\n  "vault_path": "%s",\n  "vault_id": "%s",\n' "$WORKSPACE_DIR" "$VAULT_PATH" "$VAULT_ID" >"$CONFIG_FILE"
    printf '  "knowledge_folders": %s,\n  "moc_folders": %s,\n  "daily_note_folder": "%s",\n  "ignored_folders": %s\n}\n' "$KNOWLEDGE_FOLDERS_JSON" "$MOC_FOLDERS_JSON" "$DAILY_NOTE_FOLDER" "$IGNORED_FOLDERS_JSON" >>"$CONFIG_FILE"
  fi
fi

# Skip initial vault indexing
# because it could take a long time
# with no feedback for the user

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

echo "--- 5. Finalizing Environment ---"
# Confirm that the Librarian skill and Obsidian extension are ready.
echo "Active Skills in this Workspace:"
gemini skills list

echo "Active Extensions in this Workspace:"
gemini extensions list

echo "-------------------------------------------------------"
echo "Setup Complete! The gemini-obsidian extension is now"
echo "active only within this project's workspace."
echo "-------------------------------------------------------"
