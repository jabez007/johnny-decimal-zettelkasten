#!/bin/bash

# setup-environment.sh
# Installs the latest gemini-obsidian Codex plugin globally and configures this vault.

set -euo pipefail

EXT_REPO_URL="https://github.com/jabez007/gemini-obsidian.git"
WORKSPACE_DIR="$(pwd)"
GLOBAL_EXT_ROOT="$HOME/.codex/vendor"
GLOBAL_EXT_PATH="$GLOBAL_EXT_ROOT/gemini-obsidian"
CODEX_MARKETPLACE_NAME="gemini-obsidian-repo"
CODEX_PLUGIN_NAME="gemini-obsidian"

echo "--- 1. Dependency Checks ---"
for cmd in git jq node codex npm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."

echo "--- 2. Installing global gemini-obsidian backend for Codex ---"
mkdir -p "$GLOBAL_EXT_ROOT"
if [ -d "$GLOBAL_EXT_PATH/.git" ]; then
  echo "Updating existing checkout at $GLOBAL_EXT_PATH..."
  git -C "$GLOBAL_EXT_PATH" pull --ff-only
else
  if [ -e "$GLOBAL_EXT_PATH" ]; then
    echo "Error: $GLOBAL_EXT_PATH exists but is not a git checkout."
    exit 1
  fi
  echo "Cloning $EXT_REPO_URL into $GLOBAL_EXT_PATH..."
  git clone "$EXT_REPO_URL" "$GLOBAL_EXT_PATH"
fi

echo "--- 3. Building extension dependencies ---"
pushd "$GLOBAL_EXT_PATH" >/dev/null
echo "Running npm install..."
npm install --quiet
echo "Running npm build..."
npm run build --quiet
popd >/dev/null

echo "--- 4. Configuring vault ---"
VAULT_NAME_RAW=""
if [ -t 0 ]; then
  read -rp "Enter Obsidian vault name [example]: " VAULT_NAME_RAW
fi

if [ -z "$VAULT_NAME_RAW" ]; then
  VAULT_NAME_RAW="example"
fi

VAULT_SLUG=$(echo "$VAULT_NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{1,\}/-/g' | sed 's/^-//;s/-$//')
VAULT_PATH="$WORKSPACE_DIR/vaults/$VAULT_SLUG"
PWD_BASE=$(basename "$WORKSPACE_DIR")
VAULT_ID="${PWD_BASE}_${VAULT_SLUG}"

if [ ! -d "$VAULT_PATH" ]; then
  echo "Creating new vault directory at $VAULT_PATH..."
  mkdir -p "$VAULT_PATH"
else
  echo "Using existing vault directory at $VAULT_PATH."
fi

node "$GLOBAL_EXT_PATH/dist/index.js" obsidian_set_vault \
  --path "$VAULT_PATH" \
  --workspace_path "$WORKSPACE_DIR" \
  --vault_id "$VAULT_ID"

if [ -t 0 ]; then
  read -rp "Would you like to perform initial semantic indexing now? (y/n) [n]: " DO_INDEX
  if [[ "$DO_INDEX" =~ ^[Yy]$ ]]; then
    echo "Starting semantic indexing (this may take a few minutes)..."
    node "$GLOBAL_EXT_PATH/dist/index.js" obsidian_rag_index \
      --path "$VAULT_PATH" \
      --workspace_path "$WORKSPACE_DIR" \
      --vault_id "$VAULT_ID"
  fi
fi

echo "--- 5. Installing or Updating Codex Plugin Globally ---"
MARKETPLACE_JSON=$(codex plugin marketplace list --json)
CURRENT_MARKETPLACE_ROOT=$(printf '%s' "$MARKETPLACE_JSON" | jq -r --arg name "$CODEX_MARKETPLACE_NAME" '.marketplaces[]? | select(.name == $name) | .root')

if [ -n "$CURRENT_MARKETPLACE_ROOT" ] && [ "$CURRENT_MARKETPLACE_ROOT" != "$GLOBAL_EXT_PATH" ]; then
  echo "Removing existing Codex marketplace '$CODEX_MARKETPLACE_NAME' from $CURRENT_MARKETPLACE_ROOT..."
  codex plugin marketplace remove "$CODEX_MARKETPLACE_NAME" >/dev/null
  CURRENT_MARKETPLACE_ROOT=""
fi

if [ -z "$CURRENT_MARKETPLACE_ROOT" ]; then
  echo "Adding Codex marketplace '$CODEX_MARKETPLACE_NAME' from $GLOBAL_EXT_PATH..."
  codex plugin marketplace add "$GLOBAL_EXT_PATH" >/dev/null
else
  echo "Codex marketplace '$CODEX_MARKETPLACE_NAME' already points at $GLOBAL_EXT_PATH."
fi

PLUGIN_JSON=$(codex plugin list --json)
if printf '%s' "$PLUGIN_JSON" | jq -e --arg name "$CODEX_PLUGIN_NAME" '.installed[]? | select(.name == $name)' >/dev/null; then
  echo "Refreshing installed Codex plugin '$CODEX_PLUGIN_NAME'..."
  codex plugin remove "$CODEX_PLUGIN_NAME" >/dev/null
fi

codex plugin add "$CODEX_PLUGIN_NAME@$CODEX_MARKETPLACE_NAME" >/dev/null
echo "Installed Codex plugin '$CODEX_PLUGIN_NAME' globally."

echo "--- 6. Finalizing Environment ---"

echo "-------------------------------------------------------"
echo "Setup Complete! Start a new Codex session in"
echo "$WORKSPACE_DIR so it loads AGENTS.md,"
echo ".codex/agents/, and .codex/config.toml."
echo "If Codex asks you to review project hooks,"
echo "open /hooks and trust the repo-local SessionStart hook."
echo "The Obsidian Vault plugin now lives in your global"
echo "Codex plugin configuration."
echo "-------------------------------------------------------"
