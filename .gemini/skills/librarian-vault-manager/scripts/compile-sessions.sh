#!/bin/bash
# GENERATED FILE — DO NOT EDIT. Regenerate with ./scripts/sync-assets.sh
# Backward-compatible wrapper for the repo-level session compiler.

set -euo pipefail

# Resolve from this script's own location rather than the caller's cwd, so
# invoking the wrapper from outside the worktree still finds the right repo.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Assign in two steps: `$(a || b && c)` parses as `$((a || b) && c)`, so a
# successful git call would still run pwd and capture both paths.
if ! REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../../.." && pwd)
fi
exec "$REPO_ROOT/scripts/compile-sessions.sh" "$@"
