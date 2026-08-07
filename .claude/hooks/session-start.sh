#!/bin/bash

# Loads Agent Memory context into Claude Code at session start.
# The context body itself is canonical in scripts/agent-memory-context.sh.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}
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

# Capture separately so a failing context script degrades to a diagnostic
# instead of emitting an empty additionalContext.
if ! CONTEXT=$(bash "$CONTEXT_SCRIPT" 2>&1) || [ -z "$CONTEXT" ]; then
  CONTEXT="Agent Memory: context script failed. Context restoration skipped.${CONTEXT:+ Details: $CONTEXT}"
fi

emit_context "$CONTEXT"
