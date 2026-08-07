#!/bin/bash

# migrate-v2.sh
# Upgrades an existing vault from the v1 gemini-obsidian backend to
# obsidian-vault-mcp v2.
#
# Safe to re-run: every step checks current state before acting. The script
# never touches vault note content — only host plugin registrations, LFS
# tracking patterns, and the RAG index.
#
# Usage: ./scripts/migrate-v2.sh [--yes]

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
MCP_CMD="npx -y @jabez007/obsidian-vault-mcp@2"
CONFIG_PRIMARY="$HOME/.obsidian-mcp.config.json"
CONFIG_LEGACY="$HOME/.gemini-obsidian.config.json"
ASSUME_YES=0

[ "${1:-}" = "--yes" ] && ASSUME_YES=1

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  [ -t 0 ] || return 1
  read -rp "$1 (y/n) [n]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

echo "======================================================="
echo " obsidian-vault-mcp v2 migration"
echo "======================================================="
echo ""

# --- 1. Legacy Codex plugin and marketplace --------------------------------
echo "--- 1. Legacy Codex plugin ---"
if command -v codex >/dev/null 2>&1; then
  if codex plugin list --json 2>/dev/null | jq -e '.installed[]? | select(.name == "gemini-obsidian")' >/dev/null; then
    echo "Removing legacy Codex plugin 'gemini-obsidian'..."
    codex plugin remove gemini-obsidian >/dev/null || true
  else
    echo "No legacy Codex plugin installed."
  fi
  if codex plugin marketplace list --json 2>/dev/null | jq -e '.marketplaces[]? | select(.name == "gemini-obsidian-repo")' >/dev/null; then
    echo "Removing legacy Codex marketplace 'gemini-obsidian-repo'..."
    codex plugin marketplace remove gemini-obsidian-repo >/dev/null || true
  else
    echo "No legacy Codex marketplace registered."
  fi
else
  echo "Codex CLI not installed; skipping."
fi

# --- 2. Legacy Gemini extension --------------------------------------------
echo ""
echo "--- 2. Legacy Gemini extension ---"
if command -v gemini >/dev/null 2>&1; then
  if gemini extensions list 2>&1 | grep -q "gemini-obsidian"; then
    echo "Removing legacy Gemini extension 'gemini-obsidian'..."
    gemini extensions uninstall gemini-obsidian || \
      echo "Warning: uninstall failed. Remove it manually with: gemini extensions uninstall gemini-obsidian"
  else
    echo "No legacy Gemini extension installed."
  fi
else
  echo "Gemini CLI not installed; skipping."
fi

# --- 3. Stale vendored checkout --------------------------------------------
echo ""
echo "--- 3. Stale vendored checkout ---"
VENDOR_DIR="$HOME/.codex/vendor/gemini-obsidian"
if [ -d "$VENDOR_DIR" ]; then
  echo "v1 cloned and built the backend at:"
  echo "  $VENDOR_DIR"
  echo "v2 installs from npm, so this checkout is no longer used."
  if confirm "Delete it?"; then
    rm -rf "$VENDOR_DIR"
    echo "Deleted."
  else
    echo "Left in place."
  fi
else
  echo "No stale checkout found."
fi

# --- 4. Git LFS tracking patterns ------------------------------------------
echo ""
echo "--- 4. Git LFS tracking patterns ---"
GITATTRS="$REPO_ROOT/.gitattributes"
if [ -f "$GITATTRS" ] && grep -q "\.gemini-obsidian/" "$GITATTRS"; then
  echo "Rewriting .gemini-obsidian/ LFS patterns to .obsidian-vault-mcp/..."
  # A temp file keeps this working on both GNU and BSD sed; BSD's -i
  # requires a suffix argument and would otherwise consume the script.
  sed 's#\.gemini-obsidian/#.obsidian-vault-mcp/#g' "$GITATTRS" >"$GITATTRS.tmp" \
    && mv "$GITATTRS.tmp" "$GITATTRS"
  echo "Updated $GITATTRS."
else
  echo "No legacy LFS patterns to rewrite."
fi

# --- 5. Storage directory ---------------------------------------------------
echo ""
echo "--- 5. Storage directory ---"
if [ -d "$REPO_ROOT/.gemini-obsidian" ]; then
  echo "Found $REPO_ROOT/.gemini-obsidian/."
  echo "The v2 server renames this to .obsidian-vault-mcp/ automatically on"
  echo "first access, preserving indexes and file hashes. No action needed."
else
  echo "No legacy storage directory in this workspace."
fi

# --- 6. Config file ---------------------------------------------------------
echo ""
echo "--- 6. Vault configuration ---"
if [ -f "$CONFIG_PRIMARY" ]; then
  echo "Using $CONFIG_PRIMARY."
elif [ -f "$CONFIG_LEGACY" ]; then
  echo "Only the legacy config exists: $CONFIG_LEGACY"
  echo "v2 reads it as a fallback but writes only to $CONFIG_PRIMARY."
  echo "Run your harness's setup-environment.sh to write the new file."
else
  echo "No vault configured yet. Run your harness's setup-environment.sh first."
fi

VAULT_PATH=""
for cfg in "$CONFIG_PRIMARY" "$CONFIG_LEGACY"; do
  if [ -f "$cfg" ]; then
    VAULT_PATH=$(jq -r '.vault_path // empty' "$cfg" 2>/dev/null || echo "")
    WORKSPACE_PATH=$(jq -r '.workspace_path // empty' "$cfg" 2>/dev/null || echo "")
    VAULT_ID=$(jq -r '.vault_id // empty' "$cfg" 2>/dev/null || echo "")
    [ -n "$VAULT_PATH" ] && break
  fi
done

# --- 7. Mandatory reindex ---------------------------------------------------
echo ""
echo "--- 7. RAG index rebuild (REQUIRED) ---"
echo ""
echo "v2 migrated the embedding stack from @xenova/transformers to"
echo "@huggingface/transformers. The model and 384-dimensional vectors are"
echo "unchanged, but new vectors are NOT numerically identical to old ones."
echo ""
echo "An index mixing pre- and post-upgrade chunks degrades search ranking"
echo "SILENTLY — there is no error and no warning. A one-time full rebuild is"
echo "the only fix."
echo ""

if [ -z "$VAULT_PATH" ] || [ ! -d "$VAULT_PATH" ]; then
  echo "No valid vault path found, so the rebuild cannot run here."
  echo "After configuring a vault, run:"
  echo ""
  echo "  $MCP_CMD obsidian_rag_index --force_reindex true"
  echo ""
else
  echo "Vault: $VAULT_PATH"
  if confirm "Rebuild the RAG index now? (this may take several minutes)"; then
    # shellcheck disable=SC2086
    # Omit --vault_id when the config has none: an empty identifier would
    # target the wrong index and defeat the rebuild.
    VAULT_ID_ARGS=()
    [ -n "${VAULT_ID:-}" ] && VAULT_ID_ARGS=(--vault_id "$VAULT_ID")
    $MCP_CMD obsidian_rag_index \
      --path "$VAULT_PATH" \
      --workspace_path "${WORKSPACE_PATH:-$REPO_ROOT}" \
      "${VAULT_ID_ARGS[@]}" \
      --force_reindex true
    echo "Index rebuilt."
  else
    echo ""
    echo "SKIPPED. Your index is now in a mixed state. Run this before relying"
    echo "on semantic search:"
    echo ""
    echo "  $MCP_CMD obsidian_rag_index --force_reindex true"
    echo ""
  fi
fi

# --- 8. Regenerate harness assets ------------------------------------------
echo ""
echo "--- 8. Regenerating harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

echo ""
echo "======================================================="
echo " Migration complete."
echo ""
echo " Next: run the setup script for each harness you use."
echo "   ./.claude/setup-environment.sh"
echo "   ./.codex/setup-environment.sh"
echo "   ./.gemini/setup-environment.sh"
echo "   ./.opencode/setup-environment.sh"
echo "======================================================="
