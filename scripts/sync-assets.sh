#!/bin/bash

# sync-assets.sh
# Generates the Claude Code copy of the librarian skill and each harness's
# agent definitions.
#
# Canonical sources (edit these):
#   references/librarian/*.md                          - shared doctrine
#   .agents/skills/librarian-vault-manager/SKILL.md    - skill body
#   .agents/agents/*.md                                - agent policies
#
# Generated copies (never edit by hand — this script overwrites them):
#   .claude/skills/librarian-vault-manager/SKILL.md
#   .claude/agents/*.md  .gemini/agents/*.md  .opencode/agents/*.md
#   .codex/agents/*.toml
#
# Codex, Gemini CLI, and OpenCode read the skill from .agents/skills/. Claude
# Code reads only .claude/skills/, so it gets a copy of SKILL.md. The skill
# names the doctrine by its repo-root path, references/librarian/*.md, so the
# doctrine is never copied.
#
# Codex finds .codex/agents/*.toml without a registry in .codex/config.toml.
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
CLAUDE_SKILL=".claude/skills/$SKILL_NAME"

if [ ! -e "$CANONICAL_SKILL" ]; then
  echo "Error: canonical source '$CANONICAL_SKILL' is missing."
  exit 1
fi

rm -rf "$CLAUDE_SKILL"
mkdir -p "$CLAUDE_SKILL"

# The banner goes after the YAML frontmatter, so Claude Code still parses the
# frontmatter first.
awk -v src="$CANONICAL_SKILL" '
  NR == 1 && $0 == "---" { print; in_fm = 1; next }
  in_fm && $0 == "---" {
    print; print ""
    print "<!-- GENERATED FILE — DO NOT EDIT."
    print "     Source: " src
    print "     Regenerate with: ./scripts/sync-assets.sh -->"
    in_fm = 0; next
  }
  { print }
' "$CANONICAL_SKILL" >"$CLAUDE_SKILL/SKILL.md"

echo "Synced $CLAUDE_SKILL/SKILL.md from $CANONICAL_SKILL."

# ---------------------------------------------------------------------------
# Agent policies
# ---------------------------------------------------------------------------

CANONICAL_AGENTS=".agents/agents"

if [ ! -d "$CANONICAL_AGENTS" ]; then
  echo "Error: canonical agent directory '$CANONICAL_AGENTS' is missing."
  exit 1
fi

# Each harness namespaces MCP tools differently. The setup scripts install the
# server as the obsidian-vault-mcp plugin in Claude Code and as an extension in
# Gemini CLI, and opencode.json names it obsidian-vault-mcp. Claude Code adds
# the plugin name to the tool names of a plugin's server.
CLAUDE_PREFIX="mcp__plugin_obsidian-vault-mcp_obsidian-vault-mcp__"
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
    grep) echo "grep_search" ;; glob) echo "glob" ;;
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
done

echo "Synced $AGENT_COUNT agent policies into 4 harness formats."
