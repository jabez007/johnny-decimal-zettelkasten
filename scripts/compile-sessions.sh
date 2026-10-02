#!/bin/bash
# Keep the existing entry point; Python handles timestamps and transcript formats.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$SCRIPT_DIR/compile-sessions.py" "$@"
