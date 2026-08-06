#!/bin/bash

# configure-vault.sh
# Shared vault configuration step used by every harness setup script.
#
# Prompts for a vault under vaults/, persists the selection to the shared MCP
# config (~/.obsidian-mcp.config.json), optionally builds the RAG index, and
# configures Git LFS for the binary index files.
#
# Sourced or executed by .claude/, .codex/, .gemini/, and .opencode/
# setup-environment.sh. Requires MCP_CMD to be set by the caller, or falls back
# to the published package.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MCP_CMD=${MCP_CMD:-"npx -y @jabez007/obsidian-vault-mcp@2"}

echo "--- Configuring vault ---"

VAULT_NAME_RAW=""
if [ -t 0 ]; then
  read -rp "Enter Obsidian vault name [example]: " VAULT_NAME_RAW
fi

if [ -z "$VAULT_NAME_RAW" ]; then
  VAULT_NAME_RAW="example"
fi

# Slugify: lowercase, replace non-alphanumeric with hyphens, collapse, trim ends
VAULT_SLUG=$(echo "$VAULT_NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{1,\}/-/g' | sed 's/^-//;s/-$//')

if [ -z "$VAULT_SLUG" ]; then
  echo "Error: '$VAULT_NAME_RAW' slugified to an empty name. Use at least one letter or digit."
  exit 1
fi

VAULT_PATH="$REPO_ROOT/vaults/$VAULT_SLUG"
VAULT_ID="$(basename "$REPO_ROOT")_${VAULT_SLUG}"

if [ ! -d "$VAULT_PATH" ]; then
  echo "Creating new vault directory at $VAULT_PATH..."
  mkdir -p "$VAULT_PATH"
else
  echo "Using existing vault directory at $VAULT_PATH."
fi

# Persist vault_path, workspace_path, and vault_id to ~/.obsidian-mcp.config.json
# through the server's own CLI so the format stays authoritative.
# shellcheck disable=SC2086
$MCP_CMD obsidian_set_vault \
  --path "$VAULT_PATH" \
  --workspace_path "$REPO_ROOT" \
  --vault_id "$VAULT_ID"

echo "--- Configuring Git LFS for RAG index binaries ---"
# v2 stores indexes under .obsidian-vault-mcp/ (renamed from .gemini-obsidian/).
if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
  if command -v git-lfs >/dev/null 2>&1; then
    git -C "$REPO_ROOT" lfs install --local
    git -C "$REPO_ROOT" lfs track ".obsidian-vault-mcp/**/*.lance"
    git -C "$REPO_ROOT" lfs track ".obsidian-vault-mcp/**/*.lance/**"
    git -C "$REPO_ROOT" lfs track ".obsidian-vault-mcp/**/*.onnx"
    echo "Git LFS tracking configured for .obsidian-vault-mcp/."
  else
    echo "Warning: git-lfs not found. RAG index binaries will not be tracked efficiently."
  fi
else
  echo "Skipping Git LFS setup (not a git repository or git not found)."
fi

if [ -t 0 ]; then
  read -rp "Would you like to perform initial semantic indexing now? (y/n) [n]: " DO_INDEX
  if [[ "$DO_INDEX" =~ ^[Yy]$ ]]; then
    echo "Starting semantic indexing (this may take a few minutes)..."
    # shellcheck disable=SC2086
    $MCP_CMD obsidian_rag_index \
      --path "$VAULT_PATH" \
      --workspace_path "$REPO_ROOT" \
      --vault_id "$VAULT_ID"
  fi
fi

echo ""
echo "Vault configured: $VAULT_PATH (id: $VAULT_ID)"
echo ""
echo "This template keeps multiple vaults under vaults/. The MCP server bounds"
echo "per-call vault overrides to the configured vault and workspace. To work"
echo "across several vaults in one session, export:"
echo ""
echo "  export OBSIDIAN_ALLOWED_VAULTS=\"$REPO_ROOT/vaults\""
echo ""
