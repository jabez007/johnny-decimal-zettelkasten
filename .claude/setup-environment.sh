#!/bin/bash

# setup-environment.sh (Claude Code)
# Installs the obsidian-vault-mcp v2 Claude Code plugin and configures this vault.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MARKETPLACE_URL="https://github.com/jabez007/obsidian-vault-mcp.git"
MARKETPLACE_NAME="obsidian-vault-mcp"
PLUGIN_NAME="obsidian-vault-mcp"

echo "--- 1. Dependency checks ---"
for cmd in git jq node npx claude; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."

echo "--- 2. Installing the $PLUGIN_NAME plugin ---"
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
  echo "Marketplace '$MARKETPLACE_NAME' already registered. Refreshing..."
  claude plugin marketplace update "$MARKETPLACE_NAME" >/dev/null 2>&1 || \
    echo "Note: refresh skipped or already current."
else
  echo "Adding marketplace $MARKETPLACE_URL..."
  claude plugin marketplace add "$MARKETPLACE_URL"
fi

if claude plugin list 2>/dev/null | grep -q "$PLUGIN_NAME"; then
  echo "Plugin '$PLUGIN_NAME' already installed."
else
  claude plugin install "$PLUGIN_NAME@$MARKETPLACE_NAME"
fi

echo "--- 3. Configuring vault ---"
bash "$REPO_ROOT/scripts/configure-vault.sh"

echo "--- 4. Generating per-harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

echo "--- 5. Finalizing ---"
echo "-------------------------------------------------------"
echo "Setup complete. Start Claude Code from $REPO_ROOT"
echo "so it loads CLAUDE.md, .claude/agents/, and the"
echo "SessionStart hook in .claude/settings.json."
echo ""
echo "If you are upgrading an existing vault from v1, you MUST rebuild the RAG"
echo "index once — see MIGRATION.md. A mixed old/new index degrades search"
echo "ranking silently, with no error."
echo "-------------------------------------------------------"
