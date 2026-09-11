#!/bin/bash
# Shared index dispatcher. Pull and switch branches with MCP sessions stopped.
set -euo pipefail
git lfs post-merge "$@"
REPO_ROOT=$(git rev-parse --show-toplevel)
HANDLER="$REPO_ROOT/scripts/receive-index-snapshot.sh"
if [ ! -f "$HANDLER" ]; then
  exit 0
fi
exec bash "$HANDLER" post-merge "$@"
