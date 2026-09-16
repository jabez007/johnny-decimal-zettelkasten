#!/bin/bash

# setup-environment.sh (Codex CLI)
# Installs the obsidian-vault-mcp v2 Codex plugin and configures this vault.
#
# v2 ships as an npm package and Codex can add a marketplace straight from a Git
# source, so the old ~/.codex/vendor clone-and-build step is gone.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    exec bash "$REPO_ROOT/scripts/configure-vault.sh" --help
  fi
done
MARKETPLACE_SOURCE="jabez007/obsidian-vault-mcp"
MARKETPLACE_NAME="obsidian-vault-mcp-repo"
PLUGIN_NAME="obsidian-vault-mcp"
LEGACY_MARKETPLACE_NAME="gemini-obsidian-repo"
LEGACY_PLUGIN_NAME="gemini-obsidian"

echo "--- 1. Dependency checks ---"
for cmd in git jq node npx python3 codex; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."
bash "$REPO_ROOT/scripts/configure-vault.sh" --check "$@"
python3 "$REPO_ROOT/scripts/install-global.py" --harness codex --check
for arg in "$@"; do
  if [[ "$arg" == "--check" ]]; then exit 0; fi
done

echo "--- 2. Removing legacy gemini-obsidian install, if present ---"
if codex plugin list --json 2>/dev/null | jq -e --arg n "$LEGACY_PLUGIN_NAME" '.installed[]? | select(.name == $n)' >/dev/null; then
  echo "Removing legacy plugin '$LEGACY_PLUGIN_NAME'..."
  codex plugin remove "$LEGACY_PLUGIN_NAME" >/dev/null || true
fi
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

if codex plugin list --json | jq -e --arg n "$PLUGIN_NAME" '.installed[]? | select(.name == $n and .enabled == true)' >/dev/null; then
  echo "Codex plugin '$PLUGIN_NAME' is already enabled; preserving its installation."
else
  codex plugin add "$PLUGIN_NAME@$MARKETPLACE_NAME" >/dev/null
  echo "Installed Codex plugin '$PLUGIN_NAME'."
fi

echo "--- 4. Configuring vault ---"
bash "$REPO_ROOT/scripts/configure-vault.sh" "$@"

echo "--- 5. Generating per-harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

python3 "$REPO_ROOT/scripts/install-global.py" --harness codex

echo "--- 6. Finalizing ---"
echo "-------------------------------------------------------"
echo "Setup complete. Start Codex from $REPO_ROOT so it loads"
echo "AGENTS.md, .codex/agents/, and .codex/config.toml."
echo ""
echo "If Codex prompts you to review project hooks, open /hooks"
echo "and trust the repo-local SessionStart hook."
echo ""
echo "If you are upgrading an existing vault from v1, you MUST rebuild the RAG"
echo "index once — see MIGRATION.md. A mixed old/new index degrades search"
echo "ranking silently, with no error."
echo "-------------------------------------------------------"
