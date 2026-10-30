#!/bin/bash

# setup-environment.sh (Codex CLI)
# Installs the obsidian-vault-mcp v2 Codex plugin and configures this vault.
#
# v2 ships as an npm package and Codex can add a marketplace straight from a Git
# source, so the old ~/.codex/vendor clone-and-build step is gone.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MARKETPLACE_SOURCE="jabez007/obsidian-vault-mcp"
MARKETPLACE_NAME="obsidian-vault-mcp-repo"
PLUGIN_NAME="obsidian-vault-mcp"
LEGACY_MARKETPLACE_NAME="gemini-obsidian-repo"
LEGACY_PLUGIN_NAME="gemini-obsidian"

echo "--- 1. Dependency checks ---"
for cmd in git jq node npx codex; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."

# installed_plugins NAME prints the PLUGIN@MARKETPLACE ID of each installed copy
# of NAME. codex plugin remove rejects a bare plugin name, and it accepts an
# unknown marketplace without removing anything, so use the ID Codex reports.
installed_plugins() {
  codex plugin list --json 2>/dev/null |
    jq -r --arg n "$1" '.installed[]? | select(.name == $n) | .pluginId'
}

echo "--- 2. Removing legacy gemini-obsidian install, if present ---"
for plugin in $(installed_plugins "$LEGACY_PLUGIN_NAME"); do
  echo "Removing legacy plugin '$plugin'..."
  codex plugin remove "$plugin" >/dev/null ||
    echo "Warning: could not remove '$plugin'. Run: codex plugin remove $plugin"
done
if codex plugin marketplace list --json 2>/dev/null | jq -e --arg n "$LEGACY_MARKETPLACE_NAME" '.marketplaces[]? | select(.name == $n)' >/dev/null; then
  echo "Removing legacy marketplace '$LEGACY_MARKETPLACE_NAME'..."
  codex plugin marketplace remove "$LEGACY_MARKETPLACE_NAME" >/dev/null || true
fi

echo "--- 3. Installing the $PLUGIN_NAME plugin ---"
if codex plugin marketplace list --json 2>/dev/null | jq -e --arg n "$MARKETPLACE_NAME" '.marketplaces[]? | select(.name == $n)' >/dev/null; then
  echo "Marketplace '$MARKETPLACE_NAME' already registered. Refreshing..."
  codex plugin marketplace upgrade "$MARKETPLACE_NAME" >/dev/null 2>&1 || \
    echo "Note: refresh skipped or already current."
else
  echo "Adding marketplace from $MARKETPLACE_SOURCE..."
  codex plugin marketplace add "$MARKETPLACE_SOURCE" >/dev/null
fi

for plugin in $(installed_plugins "$PLUGIN_NAME"); do
  echo "Refreshing installed plugin '$plugin'..."
  codex plugin remove "$plugin" >/dev/null
done
codex plugin add "$PLUGIN_NAME@$MARKETPLACE_NAME" >/dev/null
echo "Installed Codex plugin '$PLUGIN_NAME'."

echo "--- 4. Configuring vault ---"
bash "$REPO_ROOT/scripts/configure-vault.sh"

echo "--- 5. Generating per-harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

echo "--- 6. Finalizing ---"
echo "-------------------------------------------------------"
echo "Setup complete. Start Codex from $REPO_ROOT so it loads"
echo "AGENTS.md, .agents/skills/, and .codex/agents/. Codex reads"
echo ".codex/agents/ only after you trust the project."
echo ""
echo "If you are upgrading an existing vault from v1, you MUST rebuild the RAG"
echo "index once — see MIGRATION.md. A mixed old/new index degrades search"
echo "ranking silently, with no error."
echo "-------------------------------------------------------"
