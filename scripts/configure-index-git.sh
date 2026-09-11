#!/bin/bash

# Can be run independently after pulling template updates, without selecting
# a vault, registering plugins, or building an index.
set -euo pipefail

if ! command -v git >/dev/null 2>&1 ||
   [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
  echo "Skipping index Git setup (not in a Git working tree)."
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

echo "Configuring Git LFS for shared LanceDB data..."
if command -v git-lfs >/dev/null 2>&1; then
  # Keep Git LFS in charge of its own hooks, including pre-push.
  git lfs install --local --skip-repo

  # Earlier setup tracked embedding models. Remove those exact default rules
  # only once their files are untracked; otherwise a later git add could turn
  # an existing LFS model into a large ordinary Git blob.
  for STORAGE_ROOT in .obsidian-vault-mcp .gemini-obsidian; do
    TRACKED_MODELS=$(git ls-files -- ":(glob)$STORAGE_ROOT/**/*.onnx")
    if [ -n "$TRACKED_MODELS" ]; then
      echo "Tracked model files found; preserving any existing $STORAGE_ROOT ONNX LFS rule:"
      printf '%s\n' "$TRACKED_MODELS"
      echo "Remove these from Git tracking while keeping local copies, then rerun setup."
      echo "See docs/index-snapshots.md. Setup has not changed the staging area."
    else
      git lfs untrack "$STORAGE_ROOT/**/*.onnx"
    fi
  done

  git lfs track ".obsidian-vault-mcp/**/*.lance"
  git lfs track ".obsidian-vault-mcp/**/*.lance/**"
else
  echo "Warning: git-lfs not found. Install it and rerun this script before sharing LanceDB data."
fi

# Apply the same LF policy as the template checkout without removing custom rules.
if [ -s .gitattributes ] && [ -n "$(tail -c 1 .gitattributes)" ]; then
  printf '\n' >> .gitattributes
fi
while IFS= read -r RULE; do
  [[ -z "$RULE" || "$RULE" == \#* ]] && continue
  if ! grep -Fqx -- "$RULE" .gitattributes 2>/dev/null; then
    printf '%s\n' "$RULE" >> .gitattributes
  fi
done < "$REPO_ROOT/scripts/index-snapshot-attributes.gitattributes"

# Ignore rules cannot remove files already in the index. Report only the
# known transient files/model sidecars, not arbitrary user-ignored database data.
for STORAGE_ROOT in .obsidian-vault-mcp .gemini-obsidian; do
  TRACKED_LOCAL_FILES=$(git ls-files -- \
    ":(glob)$STORAGE_ROOT/**/*.onnx_data" \
    ":(glob)$STORAGE_ROOT/vaults/*/index.lock" \
    ":(glob)$STORAGE_ROOT/vaults/*/*.json.tmp")
  if [ -n "$TRACKED_LOCAL_FILES" ]; then
    echo "Local-only MCP files are still tracked:"
    printf '%s\n' "$TRACKED_LOCAL_FILES"
    echo "See docs/index-snapshots.md to untrack them while retaining local files."
  fi
done

if [ -n "$(git ls-files -- .obsidian-vault-mcp/vaults .gemini-obsidian/vaults)" ]; then
  echo "Tracked live MCP storage needs migration to shared snapshots."
  echo "Register each vault with its existing ID, then follow docs/index-snapshots.md."
fi

# Custom hook managers remain responsible for installing all their handlers.
if git config --get core.hooksPath >/dev/null; then
  echo "Custom core.hooksPath detected; hooks were not installed."
  echo "Integrate the snapshot and Git LFS handlers using docs/index-snapshots.md."
  exit 0
fi

# Generate stock hooks with the installed Git LFS version. Only exact stock
# hooks or our own dispatchers may be replaced. Unknown hooks stay untouched.
STOCK_DIR=$(mktemp -d)
trap 'rm -rf "$STOCK_DIR"' EXIT
if command -v git-lfs >/dev/null 2>&1; then
  (
    unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
    git -C "$STOCK_DIR" -c core.hooksPath="$STOCK_DIR/hooks" init --template= -q
    git -C "$STOCK_DIR" -c core.hooksPath="$STOCK_DIR/hooks" lfs install --local >/dev/null
  )
fi

for HOOK in pre-commit post-merge post-checkout post-rewrite pre-push post-commit; do
  HOOK_PATH=$(git rev-parse --git-path "hooks/$HOOK")
  STOCK_HOOK="$STOCK_DIR/hooks/$HOOK"
  HOOK_SOURCE="$REPO_ROOT/scripts/hooks/$HOOK.sh"
  if [ ! -f "$HOOK_SOURCE" ]; then
    HOOK_SOURCE="$STOCK_HOOK"
  fi
  [ -f "$HOOK_SOURCE" ] || continue
  if [ -e "$HOOK_PATH" ] || [ -L "$HOOK_PATH" ]; then
    if [ ! -L "$HOOK_PATH" ] && cmp -s "$HOOK_SOURCE" "$HOOK_PATH"; then
      chmod +x "$HOOK_PATH"
      continue
    fi
    if [ -L "$HOOK_PATH" ] || [ ! -f "$STOCK_HOOK" ] || ! cmp -s "$STOCK_HOOK" "$HOOK_PATH"; then
      echo "Existing $HOOK hook preserved; integrate its handlers using docs/index-snapshots.md."
      continue
    fi
  fi
  mkdir -p "$(dirname "$HOOK_PATH")"
  cp "$HOOK_SOURCE" "$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  echo "Installed $HOOK hook."
done

echo "Stage .obsidian-indexes.json and .gitattributes before the first publication."
echo "Commits update indexes; pulls and branch checkouts install shared snapshots."
echo "Keep MCP sessions stopped during pulls, branch switches, and this setup."
bash "$REPO_ROOT/scripts/receive-index-snapshot.sh" setup
