#!/bin/bash

# Stable dispatcher copied into Git's hooks directory. Resolve the checked-out
# worktree at invocation time so linked worktrees use their own implementation.
set -euo pipefail
REPO_ROOT=$(git rev-parse --show-toplevel)
HANDLER="$REPO_ROOT/scripts/check-index-snapshot.sh"
if [ ! -f "$HANDLER" ]; then
  # An older branch may predate this feature; do not break its commits.
  echo "Snapshot check unavailable in this checkout; skipping." >&2
  exit 0
fi
exec bash "$HANDLER"
