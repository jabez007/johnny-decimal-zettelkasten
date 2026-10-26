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
MCP_CMD=${MCP_CMD:-"npx -y @jabez007/obsidian-vault-mcp@2.3.0"}

echo "--- Configuring vault ---"

DEFAULT_VAULT_NAME="example"
for cfg in "$HOME/.obsidian-mcp.config.json" "$HOME/.gemini-obsidian.config.json"; do
  if [ -f "$cfg" ] && command -v jq >/dev/null 2>&1; then
    CONFIGURED_VAULT_PATH=$(jq -r '.vault_path // empty' "$cfg" 2>/dev/null || true)
    [ -n "$CONFIGURED_VAULT_PATH" ] || continue
    CONFIGURED_VAULT_PATH=${CONFIGURED_VAULT_PATH%/}
    CONFIGURED_VAULT_NAME=$(basename "$CONFIGURED_VAULT_PATH")
    if [ "$CONFIGURED_VAULT_PATH" = "$REPO_ROOT/vaults/$CONFIGURED_VAULT_NAME" ] \
      && [ -d "$CONFIGURED_VAULT_PATH" ]; then
      DEFAULT_VAULT_NAME="$CONFIGURED_VAULT_NAME"
      break
    fi
    # Say so, or an upgrade quietly retargets the configured vault.
    echo "Not offering $CONFIGURED_VAULT_PATH from $cfg: it is not a directory under $REPO_ROOT/vaults/."
  fi
done

VAULT_NAME_RAW=""
if [ -t 0 ]; then
  read -rp "Enter Obsidian vault name [$DEFAULT_VAULT_NAME]: " VAULT_NAME_RAW
fi

# The default names an existing directory, so it keeps its exact name. Only a
# typed name becomes a new slugified directory.
VAULT_DIR_NAME=""
if [ -z "$VAULT_NAME_RAW" ]; then
  VAULT_NAME_RAW="$DEFAULT_VAULT_NAME"
  VAULT_DIR_NAME="$DEFAULT_VAULT_NAME"
fi

# Slugify: lowercase, replace non-alphanumeric with hyphens, collapse, trim ends
VAULT_SLUG=$(echo "$VAULT_NAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{1,\}/-/g' | sed 's/^-//;s/-$//')

if [ -z "$VAULT_SLUG" ]; then
  echo "Error: '$VAULT_NAME_RAW' slugified to an empty name. Use at least one letter or digit."
  exit 1
fi

VAULT_PATH="$REPO_ROOT/vaults/${VAULT_DIR_NAME:-$VAULT_SLUG}"
VAULT_ID="$(basename "$REPO_ROOT")_${VAULT_SLUG}"

if [ ! -d "$VAULT_PATH" ]; then
  echo "Creating new vault directory at $VAULT_PATH..."
  mkdir -p "$VAULT_PATH"
else
  echo "Using existing vault directory at $VAULT_PATH."
fi

# Reuse the committed ID when a clone has a different directory name.
VAULT_ID=$(node "$REPO_ROOT/scripts/index-snapshots.mjs" register --vault "$VAULT_PATH" --id "$VAULT_ID")

# Persist vault_path, workspace_path, and vault_id to ~/.obsidian-mcp.config.json
# through the server's own CLI so the format stays authoritative.
# shellcheck disable=SC2086
$MCP_CMD obsidian_set_vault \
  --path "$VAULT_PATH" \
  --workspace_path "$REPO_ROOT" \
  --vault_id "$VAULT_ID"

bash "$REPO_ROOT/scripts/configure-index-git.sh"

if [ -t 0 ] && [ ! -f "$REPO_ROOT/.obsidian-vault-mcp/shared/$VAULT_ID/snapshot.json" ]; then
  read -rp "Would you like to perform semantic indexing on this machine now? (y/n) [n]: " DO_INDEX
  if [[ "$DO_INDEX" =~ ^[Yy]$ ]]; then
    echo "Starting semantic indexing (this may take a few minutes)..."
    # shellcheck disable=SC2086
    $MCP_CMD obsidian_rag_index \
      --vault_path "$VAULT_PATH" \
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
