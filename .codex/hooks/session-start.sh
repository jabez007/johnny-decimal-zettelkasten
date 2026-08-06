#!/bin/bash

# Loads Agent Memory context into Codex at session start.
# The context body itself is canonical in scripts/agent-memory-context.sh.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
CONTEXT_SCRIPT="$REPO_ROOT/scripts/agent-memory-context.sh"

emit_context() {
  jq -n --arg context "$1" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $context
    }
  }'
}

if [ ! -f "$CONTEXT_SCRIPT" ]; then
  emit_context "Agent Memory: $CONTEXT_SCRIPT is missing. Context restoration skipped."
  exit 0
fi

emit_context "$(bash "$CONTEXT_SCRIPT")"
