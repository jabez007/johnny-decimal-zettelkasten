#!/bin/bash

# setup-environment.sh
# Configures the gemini-obsidian extension for the Librarian project.

set -e

echo "--- 1. Installing gemini-obsidian extension globally ---"
# This allows the Gemini CLI to discover the extension's code.
gemini extensions install https://github.com/jabez007/gemini-obsidian --consent

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

echo "--- 3. Configuring Scoped Activation ---"
# Disable globally so it doesn't interfere with other projects.
gemini extensions disable gemini-obsidian --scope=user

# Enable specifically for this workspace.
gemini extensions enable gemini-obsidian --scope=workspace

# Set workspace isolated storage path in the global config.
# We use $HOME instead of ~ for better script portability and to allow for safe quoting.
# We only set the workspace_path to allow the user to select their vault interactively.
CONFIG_FILE="$HOME/.gemini-obsidian.config.json"
WORKSPACE_DIR="$(pwd)"
if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
  echo "Updating $CONFIG_FILE with workspace_path..."
  # Use a temporary file for safe redirection
  jq --arg wp "$WORKSPACE_DIR" '.workspace_path = $wp' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
else
  echo "{\"workspace_path\":\"$WORKSPACE_DIR\"}" > "$CONFIG_FILE"
fi

echo "--- 4. Configuring Git LFS for binary files ---"
# Since LanceDB datasets contain binary files, Git LFS should be used to store them efficiently.
# Check if git is available before running.
if command -v git >/dev/null 2>&1 && [ -d ".git" ]; then
  if command -v git-lfs >/dev/null 2>&1; then
    echo "Initializing Git LFS..."
    git lfs install --local
    git lfs track ".gemini-obsidian/**/*.lance"
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
