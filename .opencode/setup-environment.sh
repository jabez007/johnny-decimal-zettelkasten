#!/bin/bash

# setup-environment.sh (OpenCode)
# Configures this vault for OpenCode.
#
# OpenCode reads the repo-root opencode.json, which launches the
# obsidian-vault-mcp v2 server through npx — there is no plugin to install.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

echo "--- 1. Dependency checks ---"
for cmd in git jq node npx opencode; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."

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
npx -y @jabez007/obsidian-vault-mcp@2 --help >/dev/null 2>&1 || \
  echo "Note: could not pre-warm the npx cache; it will resolve on first use."

echo "--- 4. Configuring vault ---"
bash "$REPO_ROOT/scripts/configure-vault.sh"

echo "--- 5. Generating per-harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

echo "--- 6. Finalizing ---"
echo "-------------------------------------------------------"
echo "Setup complete. Start OpenCode from $REPO_ROOT"
echo "so it loads opencode.json, AGENTS.md, and .opencode/agents/."
echo ""
echo "Note: OpenCode has no command-based SessionStart hook, so the Recent"
echo "Activity Map is not injected automatically. AGENTS.md carries the"
echo "standing rules, and agents should read recent JRNL/AGNT/ logs when"
echo "resuming earlier work."
echo ""
echo "If you are upgrading an existing vault from v1, you MUST rebuild the RAG"
echo "index once — see MIGRATION.md. A mixed old/new index degrades search"
echo "ranking silently, with no error."
echo "-------------------------------------------------------"
