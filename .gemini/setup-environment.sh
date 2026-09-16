#!/bin/bash

# setup-environment.sh (Gemini CLI)
# Installs the obsidian-vault-mcp v2 Gemini extension and configures this vault.
#
# v2 ships as an npm package, so there is no longer a clone/build step: the
# extension manifest launches the server through npx.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    exec bash "$REPO_ROOT/scripts/configure-vault.sh" --help
  fi
done
EXT_REPO_URL="https://github.com/jabez007/obsidian-vault-mcp"
EXT_NAME="obsidian-vault-mcp"
LEGACY_EXT_NAME="gemini-obsidian"

echo "--- 1. Dependency checks ---"
for cmd in git jq node npx python3 gemini; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done
echo "Required commands found."
bash "$REPO_ROOT/scripts/configure-vault.sh" --check "$@"
python3 "$REPO_ROOT/scripts/install-global.py" --harness gemini --check
for arg in "$@"; do
  if [[ "$arg" == "--check" ]]; then exit 0; fi
done

echo "--- 2. Installing the $EXT_NAME extension ---"
EXT_LIST=$(gemini extensions list 2>&1 || true)

# Remove the legacy extension whenever it is present. Skipping this when v2 is
# also installed would leave the v1 server running alongside it.
if grep -q "$LEGACY_EXT_NAME" <<<"$EXT_LIST"; then
  echo "Found the legacy '$LEGACY_EXT_NAME' extension. Removing it..."
  if ! gemini extensions uninstall "$LEGACY_EXT_NAME"; then
    echo "Error: could not uninstall '$LEGACY_EXT_NAME'."
    echo "Both versions would run at once. Remove it manually, then re-run:"
    echo "  gemini extensions uninstall $LEGACY_EXT_NAME"
    exit 1
  fi
fi

if grep -q "$EXT_NAME" <<<"$EXT_LIST"; then
  echo "Extension '$EXT_NAME' already installed. Updating..."
  # A non-zero exit here also covers "already current", so this is not fatal --
  # but it must be visible, since a genuinely failed update otherwise reaches
  # "Setup complete." looking like success.
  if ! gemini extensions update "$EXT_NAME"; then
    echo "WARNING: 'gemini extensions update $EXT_NAME' returned non-zero."
    echo "         This is expected when already current, but if the vault"
    echo "         tools misbehave, reinstall with:"
    echo "           gemini extensions uninstall $EXT_NAME"
    echo "           gemini extensions install $EXT_REPO_URL --consent"
    UPDATE_WARNED=1
  fi
else
  gemini extensions install "$EXT_REPO_URL" --consent
fi

echo "--- 3. Configuring vault ---"
bash "$REPO_ROOT/scripts/configure-vault.sh" "$@"

echo "--- 4. Generating per-harness assets ---"
bash "$REPO_ROOT/scripts/sync-assets.sh"

python3 "$REPO_ROOT/scripts/install-global.py" --harness gemini

echo "--- 6. Finalizing ---"
echo "-------------------------------------------------------"
echo "Setup complete."
echo ""
echo "  Extension: $EXT_NAME (launched via npx, no local build)"
echo "  Agents:    .gemini/agents/"
echo "  Global:    Research, journal capture, and template instructions"
if [ -n "${UPDATE_WARNED:-}" ]; then
  echo ""
  echo "  NOTE: the extension update reported an error above. Verify the"
  echo "        vault tools work before relying on this setup."
fi
echo ""
echo "If you are upgrading an existing vault from v1, you MUST rebuild the RAG"
echo "index once — see MIGRATION.md. A mixed old/new index degrades search"
echo "ranking silently, with no error."
echo "-------------------------------------------------------"
