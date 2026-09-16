#!/bin/bash
# Configure the vault owned by this checkout, independent of the caller's cwd.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$SCRIPT_DIR/configure-vault.py" "$@"
