#!/bin/bash

# setup-environment.sh (Claude Code)
# Installs the obsidian-vault-mcp v2 Claude Code plugin and configures this vault.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    exec bash "$REPO_ROOT/scripts/configure-vault.sh" --help
  fi
done
MARKETPLACE_URL="https://github.com/jabez007/obsidian-vault-mcp.git"
MARKETPLACE_NAME="obsidian-vault-mcp"
PLUGIN_NAME="obsidian-vault-mcp"

echo "--- 1. Dependency checks ---"
for cmd in git jq node npx python3 claude; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."
bash "$REPO_ROOT/scripts/configure-vault.sh" --check "$@"
python3 "$REPO_ROOT/scripts/install-global.py" --harness claude --check
for arg in "$@"; do
  if [[ "$arg" == "--check" ]]; then exit 0; fi
done

echo "--- 2. Installing the $PLUGIN_NAME plugin ---"
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
  echo "Marketplace '$MARKETPLACE_NAME' already registered. Refreshing..."
  claude plugin marketplace update "$MARKETPLACE_NAME" >/dev/null 2>&1 || \
    echo "Note: refresh skipped or already current."
else
  echo "Adding marketplace $MARKETPLACE_URL..."
  claude plugin marketplace add "$MARKETPLACE_URL"
fi

if claude plugin list --json | jq -e --arg id "$PLUGIN_NAME@$MARKETPLACE_NAME" 'any(.[]; .id == $id and .scope == "user" and .enabled == true)' >/dev/null; then
  echo "Plugin '$PLUGIN_NAME' already enabled at user scope."
else
  claude plugin install "$PLUGIN_NAME@$MARKETPLACE_NAME" --scope user
fi
claude plugin enable "$PLUGIN_NAME@$MARKETPLACE_NAME" --scope user

echo "--- 3. Configuring vault ---"
bash "$REPO_ROOT/scripts/configure-vault.sh" "$@"

echo "--- 4. Generating per-harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

python3 "$REPO_ROOT/scripts/install-global.py" --harness claude

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
