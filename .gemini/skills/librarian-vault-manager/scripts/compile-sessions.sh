#!/bin/bash
# Backward-compatible wrapper for the repo-level session compiler.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exec "$REPO_ROOT/scripts/compile-sessions.sh" "$@"
