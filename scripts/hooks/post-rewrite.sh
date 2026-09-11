#!/bin/bash
# Shared index dispatcher. Pull and switch branches with MCP sessions stopped.
set -euo pipefail
# Consume Git's rewritten-commit list before doing other work.
cat >/dev/null
REPO_ROOT=$(git rev-parse --show-toplevel)
HANDLER="$REPO_ROOT/scripts/receive-index-snapshot.sh"
if [ ! -f "$HANDLER" ]; then
  exit 0
fi
exec bash "$HANDLER" post-rewrite "$@"
