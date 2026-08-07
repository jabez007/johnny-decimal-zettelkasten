#!/bin/bash

# sync-assets.sh
# Generates per-harness copies of the shared librarian doctrine, skill, and
# agent policies.
#
# Canonical sources (edit these):
#   references/librarian/*.md                          - shared doctrine
#   .agents/skills/librarian-vault-manager/SKILL.md    - skill body
#   .agents/agents/*.md                                - agent policies
#
# Generated copies (never edit by hand — this script overwrites them):
#   .claude/skills/librarian-vault-manager/   .claude/agents/*.md
#   .gemini/skills/librarian-vault-manager/   .gemini/agents/*.md
#                                             .opencode/agents/*.md
#                                             .codex/agents/*.toml
#                                             .codex/config.toml
#
# Codex reads the canonical .agents/skills/ directory directly, so it needs no
# generated skill copy. OpenCode discovers skills through Claude Code
# compatibility and picks up the .claude/skills/ copy.
#
# Agent policies are written once in .agents/agents/ and emitted into each
# harness's own format. Bodies reference MCP tools through a {{MCP_PREFIX}}
# placeholder, since every harness namespaces MCP tools differently.
#
# Run after editing any canonical source. CI reruns this and fails if the
# working tree changes, so generated copies cannot drift silently.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

SKILL_NAME="librarian-vault-manager"
CANONICAL_SKILL=".agents/skills/$SKILL_NAME/SKILL.md"
CANONICAL_DOCTRINE="references/librarian"
TARGETS=(".claude/skills/$SKILL_NAME" ".gemini/skills/$SKILL_NAME")

BANNER="<!-- GENERATED FILE — DO NOT EDIT.
     Source: $CANONICAL_SKILL
     Regenerate with: ./scripts/sync-assets.sh -->"

for required in "$CANONICAL_SKILL" "$CANONICAL_DOCTRINE"; do
  if [ ! -e "$required" ]; then
    echo "Error: canonical source '$required' is missing."
    exit 1
  fi
done

for target in "${TARGETS[@]}"; do
  echo "Generating $target/"

  rm -rf "$target"
  mkdir -p "$target/references" "$target/scripts"

  # SKILL.md: canonical body with a generated-file banner inserted after the
  # YAML frontmatter, so harness frontmatter parsing still sees it first.
  awk -v banner="$BANNER" '
    NR == 1 && $0 == "---" { print; in_fm = 1; next }
    in_fm && $0 == "---"   { print; print ""; print banner; in_fm = 0; next }
    { print }
  ' "$CANONICAL_SKILL" >"$target/SKILL.md"

  # Doctrine: copied so each harness skill is self-contained. The skill body
  # refers to these as references/librarian/*.md, which resolves from the repo
  # root; the bundled copy covers harnesses that sandbox skills to their own
  # directory.
  cp "$CANONICAL_DOCTRINE"/*.md "$target/references/"

  # Backward-compatible wrapper for the repo-level session compiler.
  cat >"$target/scripts/compile-sessions.sh" <<'WRAPPER'
#!/bin/bash
# GENERATED FILE — DO NOT EDIT. Regenerate with ./scripts/sync-assets.sh
# Backward-compatible wrapper for the repo-level session compiler.

set -euo pipefail

# Resolve from this script's own location rather than the caller's cwd, so
# invoking the wrapper from outside the worktree still finds the right repo.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../../.." && pwd)
exec "$REPO_ROOT/scripts/compile-sessions.sh" "$@"
WRAPPER
  chmod +x "$target/scripts/compile-sessions.sh"
done

echo ""
echo "Synced ${#TARGETS[@]} harness skill copies from $CANONICAL_SKILL."

# ---------------------------------------------------------------------------
# Agent policies
# ---------------------------------------------------------------------------

CANONICAL_AGENTS=".agents/agents"

if [ ! -d "$CANONICAL_AGENTS" ]; then
  echo "Error: canonical agent directory '$CANONICAL_AGENTS' is missing."
  exit 1
fi

# Each harness namespaces MCP tools differently.
CLAUDE_PREFIX="mcp__obsidian-vault-mcp__"
GEMINI_PREFIX="mcp_obsidian-vault-mcp_"
OPENCODE_PREFIX="obsidian-vault-mcp_"

# Neutral capability -> harness-native tool name.
claude_tool() {
  case "$1" in
    read) echo "Read" ;; write) echo "Write" ;; edit) echo "Edit" ;;
    grep) echo "Grep" ;; glob) echo "Glob" ;;  bash) echo "Bash" ;;
    *) echo "" ;;
  esac
}

gemini_tool() {
  case "$1" in
    read) echo "read_file" ;; write) echo "write_file" ;; edit) echo "replace" ;;
    grep) echo "grep_search" ;; glob) echo "list_directory" ;;
    bash) echo "run_shell_command" ;;
    *) echo "" ;;
  esac
}

# Read one scalar/list value out of the canonical frontmatter.
fm_value() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, key ": ") == 1 { print substr($0, length(key) + 3); exit }
  ' "$1"
}

# Body = everything after the closing frontmatter delimiter.
fm_body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next }
       fm && $0 == "---" { fm = 0; seen = 1; next }
       seen { print }' "$1"
}

# "[a, b, c]" -> "a b c"
unlist() {
  echo "$1" | sed 's/^\[//; s/\]$//; s/,//g'
}

rm -rf .claude/agents .gemini/agents .opencode/agents .codex/agents
mkdir -p .claude/agents .gemini/agents .opencode/agents .codex/agents

CODEX_REGISTRY=""
AGENT_COUNT=0

for src in "$CANONICAL_AGENTS"/*.md; do
  [ -e "$src" ] || continue
  name=$(fm_value "$src" name)
  description=$(fm_value "$src" description)
  readonly_flag=$(fm_value "$src" readonly)
  capabilities=$(unlist "$(fm_value "$src" capabilities)")
  mcp_tools=$(unlist "$(fm_value "$src" mcp_tools)")
  nicknames=$(unlist "$(fm_value "$src" nicknames)")
  # Optional: restricts filesystem writes to a single path pattern. Harnesses
  # cannot scope a write tool by path, so the scope is enforced by prompting
  # where that is supported and stated as a hard rule in the body everywhere.
  write_scope=$(fm_value "$src" write_scope)
  body=$(fm_body "$src")

  if [ -n "$write_scope" ]; then
    body="$body

## Filesystem Write Scope

Your filesystem write tool is permitted for **\`$write_scope\`** and nothing
else. Every other file you create goes through the Obsidian MCP tools, which
enforce the vault boundary. Check the path against that pattern before each
direct write; if it does not match, you are using the wrong tool."
  fi

  AGENT_COUNT=$((AGENT_COUNT + 1))

  # --- Claude Code: comma-separated tool list, mcp__server__tool prefix ------
  claude_tools=""
  for cap in $capabilities; do
    t=$(claude_tool "$cap")
    [ -n "$t" ] && claude_tools="${claude_tools:+$claude_tools, }$t"
  done
  for tool in $mcp_tools; do
    claude_tools="${claude_tools:+$claude_tools, }${CLAUDE_PREFIX}${tool}"
  done

  {
    echo "---"
    echo "name: $name"
    echo "description: $description"
    echo "tools: $claude_tools"
    echo "model: inherit"
    echo "---"
    echo ""
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source: $src"
    echo "     Regenerate with: ./scripts/sync-assets.sh -->"
    echo "$body" | sed "s/{{MCP_PREFIX}}/$CLAUDE_PREFIX/g"
  } >".claude/agents/$name.md"

  # --- Gemini CLI: YAML list of tools, mcp_server_tool prefix ---------------
  {
    echo "---"
    echo "name: $name"
    echo "description: $description"
    echo "tools:"
    for cap in $capabilities; do
      t=$(gemini_tool "$cap")
      [ -n "$t" ] && echo "  - $t"
    done
    for tool in $mcp_tools; do
      echo "  - ${GEMINI_PREFIX}${tool}"
    done
    echo "---"
    echo ""
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source: $src"
    echo "     Regenerate with: ./scripts/sync-assets.sh -->"
    echo "$body" | sed "s/{{MCP_PREFIX}}/$GEMINI_PREFIX/g"
  } >".gemini/agents/$name.md"

  # --- OpenCode: permission map rather than a tool list ---------------------
  # OpenCode has no per-agent tool allowlist, so an agent would otherwise
  # inherit every MCP tool the server exposes. Deny the whole namespace and
  # re-allow only this agent's declared tools, matching the explicit
  # allowlists the other three harnesses get.
  {
    echo "---"
    echo "description: $description"
    echo "mode: subagent"
    echo "permission:"
    # Derive filesystem permissions from the declared capabilities, not from
    # the readonly flag. An agent that writes only through MCP has no business
    # editing the working tree, and the other harnesses already withhold their
    # Write tool from it — this keeps OpenCode from being the permissive one.
    case " $capabilities " in
      *" write "*|*" edit "*)
        # A scoped writer prompts, since no harness can bound a write tool to a
        # path pattern. The prompt is the only real check on the scope rule.
        if [ -n "$write_scope" ]; then echo "  edit: ask"; else echo "  edit: allow"; fi
        ;;
      *) echo "  edit: deny" ;;
    esac
    if [ "$readonly_flag" = "true" ]; then
      echo "  bash: deny"
    else
      case " $capabilities " in
        *" bash "*) echo "  bash: ask" ;;
        *)          echo "  bash: deny" ;;
      esac
    fi
    echo "  webfetch: deny"
    echo "  \"${OPENCODE_PREFIX}*\": deny"
    for tool in $mcp_tools; do
      echo "  \"${OPENCODE_PREFIX}${tool}\": allow"
    done
    echo "---"
    echo ""
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source: $src"
    echo "     Regenerate with: ./scripts/sync-assets.sh -->"
    echo "$body" | sed "s/{{MCP_PREFIX}}/$OPENCODE_PREFIX/g"
  } >".opencode/agents/$name.md"

  # --- Codex CLI: TOML with developer_instructions -------------------------
  # Codex prose uses bare tool names; the plugin namespaces them at call time.
  codex_body=$(echo "$body" | sed "s/{{MCP_PREFIX}}//g")
  if grep -q '"""' <<<"$codex_body"; then
    echo "Error: $src body contains a TOML multiline delimiter (\"\"\")."
    exit 1
  fi

  codex_nicks=""
  for nick in $nicknames; do
    codex_nicks="${codex_nicks:+$codex_nicks, }\"$nick\""
  done

  {
    echo "# GENERATED FILE — DO NOT EDIT."
    echo "# Source: $src"
    echo "# Regenerate with: ./scripts/sync-assets.sh"
    echo "name = \"$name\""
    echo "description = \"${description//\"/\\\"}\""
    echo "developer_instructions = \"\"\""
    echo "$codex_body"
    echo "\"\"\""
    echo "nickname_candidates = [$codex_nicks]"
  } >".codex/agents/$name.toml"

  CODEX_REGISTRY="$CODEX_REGISTRY

[agents.\"$name\"]
description = \"${description//\"/\\\"}\"
config_file = \"./agents/$name.toml\"
nickname_candidates = [$codex_nicks]"
done

# --- Codex config.toml: generated registry plus the static hook block -------
{
  echo "# GENERATED FILE — DO NOT EDIT."
  echo "# Agent entries are generated from $CANONICAL_AGENTS/*.md."
  echo "# Regenerate with: ./scripts/sync-assets.sh"
  echo ""
  echo "[features]"
  echo "hooks = true"
  echo ""
  echo "[agents]"
  echo "max_depth = 1"
  echo "$CODEX_REGISTRY"
  echo ""
  echo "[[hooks.SessionStart]]"
  echo 'matcher = "startup|resume"'
  echo ""
  echo "[[hooks.SessionStart.hooks]]"
  echo 'type = "command"'
  echo "command = 'bash \"\$(git rev-parse --show-toplevel)/.codex/hooks/session-start.sh\"'"
  echo "timeout = 30"
  echo 'statusMessage = "Loading Agent Memory context"'
} >".codex/config.toml"

echo "Synced $AGENT_COUNT agent policies into 4 harness formats."
