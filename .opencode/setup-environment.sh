#!/bin/bash

# setup-environment.sh (OpenCode)
# Installs global MCP access and template policy; keeps management local.
#
# Global and repo-local OpenCode configuration launch the same MCP backend.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    exec bash "$REPO_ROOT/scripts/configure-vault.sh" --help
  fi
done

echo "--- 1. Dependency checks ---"
for cmd in git jq node npx python3 opencode; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."
bash "$REPO_ROOT/scripts/configure-vault.sh" --check "$@"
python3 "$REPO_ROOT/scripts/install-global.py" --harness opencode --check
for arg in "$@"; do
  if [[ "$arg" == "--check" ]]; then exit 0; fi
done

echo "--- 2. Verifying MCP server registration ---"
if [ ! -f "$REPO_ROOT/opencode.json" ]; then
  echo "Error: $REPO_ROOT/opencode.json is missing."
  exit 1
fi
if ! jq -e '.mcp["obsidian-vault-mcp"]' "$REPO_ROOT/opencode.json" >/dev/null; then
  echo "Error: opencode.json does not register the obsidian-vault-mcp server."
  exit 1
fi
echo "opencode.json registers obsidian-vault-mcp."

echo "--- 3. Warming the MCP package cache ---"
# Pull the package now so the first OpenCode session does not stall on npx.
npx -y @jabez007/obsidian-vault-mcp@2.1.0 --help >/dev/null 2>&1 || \
  echo "Note: could not pre-warm the npx cache; it will resolve on first use."

echo "--- 4. Configuring vault ---"
bash "$REPO_ROOT/scripts/configure-vault.sh" "$@"

echo "--- 5. Generating per-harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

python3 "$REPO_ROOT/scripts/install-global.py" --harness opencode

echo "--- 6. Finalizing ---"
echo "-------------------------------------------------------"
echo "Setup complete. Start OpenCode from $REPO_ROOT"
echo "so it loads opencode.json, AGENTS.md, and .opencode/agents/."
echo ""
echo "Research and JRNL capture are available from any project."
echo "Management agents are loaded only inside this vault repository."
echo ""
echo "If you are upgrading an existing vault from v1, you MUST rebuild the RAG"
echo "index once — see MIGRATION.md. A mixed old/new index degrades search"
echo "ranking silently, with no error."
echo "-------------------------------------------------------"
