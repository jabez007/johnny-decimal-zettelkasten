#!/bin/bash
set -euo pipefail
REPO_ROOT=$(git rev-parse --show-toplevel)
exec node "$REPO_ROOT/scripts/index-snapshots.mjs" hook "$@"
