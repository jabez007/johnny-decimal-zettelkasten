#!/bin/bash

# run-tests.sh
# Exercises the template's setup and migration scripts inside the container.
#
# Works on a copy of the read-only /repo mount, so the host working tree is
# never modified. Every check is non-interactive.

set -uo pipefail

REPO_SRC=${REPO_SRC:-/repo}
WORK_DIR=${WORK_DIR:-/work/repo}
MCP_CMD="npx -y @jabez007/obsidian-vault-mcp@2"

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  FAILED_NAMES+=("$1")
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
  [ -n "${2:-}" ] && printf '       %s\n' "$2"
}

check() {
  local name=$1; shift
  local out
  if out=$("$@" 2>&1); then
    pass "$name"
  else
    fail "$name" "$(echo "$out" | tail -3 | tr '\n' ' ')"
  fi
}

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

echo "======================================================="
echo " johnny-decimal-zettelkasten test harness"
echo "======================================================="
echo "  node    $(node --version)"
echo "  git     $(git --version | awk '{print $3}')"
echo "  jq      $(jq --version)"
echo "  sqlite3 $(sqlite3 --version | awk '{print $1}')"
echo "  HOME    $HOME"

# --- Set up an isolated working copy ---------------------------------------
section "0. Working copy"

# Clear any session logs left by a previous run. A fresh container gets this
# for free, but local runs reuse HOME and would otherwise see stale logs and
# report false results.
rm -rf "$HOME/.claude/projects" \
       "$HOME/.codex/sessions" \
       "$HOME/.gemini/tmp" \
       "$HOME/.local/share/opencode"

rm -rf "$WORK_DIR"
mkdir -p "$(dirname "$WORK_DIR")"
cp -r "$REPO_SRC" "$WORK_DIR" 2>/dev/null
cd "$WORK_DIR" || { echo "cannot enter $WORK_DIR"; exit 1; }

# The copy needs to be a git repo: the scripts locate the root via git.
rm -rf .git
git init -q .
git config user.email tester@example.com
git config user.name Tester
git add -A >/dev/null 2>&1
git commit -qm "test baseline" >/dev/null 2>&1
pass "isolated working copy at $WORK_DIR"

# --- 1. Static checks -------------------------------------------------------
section "1. Static checks"

mapfile -t SH_FILES < <(find . -name '*.sh' \
  -not -path './.claude/skills/*' \
  -not -path './.gemini/skills/*' \
  -not -path './config/*')
check "shellcheck (${#SH_FILES[@]} scripts)" shellcheck --severity=warning "${SH_FILES[@]}"

for f in .claude/settings.json opencode.json; do
  check "valid JSON: $f" jq -e . "$f"
done

check "opencode.json registers obsidian-vault-mcp" \
  jq -e '.mcp["obsidian-vault-mcp"].command | index("@jabez007/obsidian-vault-mcp@2")' opencode.json

python3 - <<'PY' && pass "all .codex TOML parses" || fail "all .codex TOML parses"
import tomllib, glob, os, sys
root = os.environ.get("WORK_DIR", "/work/repo")
try:
    cfg_path = os.path.join(root, ".codex/config.toml")
    for f in [cfg_path] + glob.glob(os.path.join(root, ".codex/agents/*.toml")):
        tomllib.load(open(f, "rb"))
    cfg = tomllib.load(open(cfg_path, "rb"))
    agents = [k for k in cfg["agents"] if k != "max_depth"]
    assert len(agents) == 8, f"expected 8 agents, got {len(agents)}"
    assert "SessionStart" in cfg["hooks"], "SessionStart hook missing"
except Exception as e:
    print(e); sys.exit(1)
PY

# --- 2. Asset generation ----------------------------------------------------
section "2. Asset generation"

check "sync-assets.sh runs" bash scripts/sync-assets.sh

A=$(find .claude .gemini .opencode .codex -type f | sort | xargs sha256sum | sha256sum)
bash scripts/sync-assets.sh >/dev/null 2>&1
B=$(find .claude .gemini .opencode .codex -type f | sort | xargs sha256sum | sha256sum)
if [ "$A" = "$B" ]; then pass "sync-assets.sh is idempotent"; else fail "sync-assets.sh is idempotent"; fi

if git diff --quiet; then
  pass "committed assets match generator output (CI drift gate)"
else
  fail "committed assets match generator output (CI drift gate)" \
       "$(git diff --name-only | tr '\n' ' ')"
fi

for h in claude gemini; do
  ok=1
  for f in copilot-instructions johnny-decimal philosophy zettelkasten; do
    cmp -s "references/librarian/$f.md" ".$h/skills/librarian-vault-manager/references/$f.md" || ok=0
  done
  [ "$ok" = 1 ] && pass "doctrine identical in .$h/skills/" || fail "doctrine identical in .$h/skills/"
done

for d in .claude/agents .gemini/agents .opencode/agents .codex/agents; do
  n=$(find "$d" -type f | wc -l)
  [ "$n" = 8 ] && pass "$d has 8 agents" || fail "$d has 8 agents" "found $n"
done

if grep -rq '{{MCP_PREFIX}}' .claude .gemini .opencode .codex 2>/dev/null; then
  fail "no unsubstituted {{MCP_PREFIX}} in generated output"
else
  pass "no unsubstituted {{MCP_PREFIX}} in generated output"
fi

check "Claude agents use mcp__ prefix" \
  grep -q 'mcp__obsidian-vault-mcp__obsidian_read_note' .claude/agents/librarian.md
check "Gemini agents use mcp_ prefix" \
  grep -q 'mcp_obsidian-vault-mcp_obsidian_read_note' .gemini/agents/librarian.md

# --- 3. MCP server integration ---------------------------------------------
section "3. MCP server integration"

VAULT="$WORK_DIR/vaults/example"
check "obsidian_set_vault writes config" \
  $MCP_CMD obsidian_set_vault --path "$VAULT" --workspace_path "$WORK_DIR" --vault_id test_example

if [ -f "$HOME/.obsidian-mcp.config.json" ]; then
  pass "MCP config created in HOME"
  got=$(jq -r '.vault_path' "$HOME/.obsidian-mcp.config.json")
  [ "${got%/}" = "$VAULT" ] && pass "config vault_path is correct" \
    || fail "config vault_path is correct" "got $got"
else
  fail "MCP config created in HOME"
fi

check "obsidian_list_notes reads the vault" \
  $MCP_CMD obsidian_list_notes --path "$VAULT" --workspace_path "$WORK_DIR" --vault_id test_example

if [ -n "${SKIP_RAG_INDEX:-}" ]; then
  echo "  SKIP RAG indexing (SKIP_RAG_INDEX set)"
else
  echo "  (indexing downloads the embedding model on first run; this is slow)"
  if $MCP_CMD obsidian_rag_index --path "$VAULT" --workspace_path "$WORK_DIR" \
       --vault_id test_example --force_reindex true >/tmp/index.log 2>&1; then
    pass "obsidian_rag_index --force_reindex true"
    if [ -d "$WORK_DIR/.obsidian-vault-mcp" ]; then
      pass "index written to .obsidian-vault-mcp/ (v2 storage name)"
    else
      fail "index written to .obsidian-vault-mcp/ (v2 storage name)" \
           "found: $(find "$WORK_DIR" -maxdepth 1 -name '.*obsidian*' -printf '%f ' 2>/dev/null)"
    fi
    if $MCP_CMD obsidian_rag_query --query "Johnny Decimal index" --path "$VAULT" \
         --workspace_path "$WORK_DIR" --vault_id test_example >/tmp/query.log 2>&1; then
      pass "obsidian_rag_query returns results"
      if grep -q 'undefined' /tmp/query.log; then
        fail "rag_query relevance score renders" "output contains 'undefined'"
      else
        pass "rag_query relevance score renders"
      fi
    else
      fail "obsidian_rag_query returns results" "$(tail -3 /tmp/query.log | tr '\n' ' ')"
    fi
  else
    fail "obsidian_rag_index --force_reindex true" "$(tail -5 /tmp/index.log | tr '\n' ' ')"
  fi
fi

# --- 4. Agent memory context ------------------------------------------------
section "4. Agent memory context"

CTX=$(bash scripts/agent-memory-context.sh 2>&1)
echo "$CTX" | grep -q 'Agent Memory SOPs' && pass "context script emits SOPs" \
  || fail "context script emits SOPs"
echo "$CTX" | grep -q 'obsidian-vault-mcp' && pass "context references the v2 server key" \
  || fail "context references the v2 server key"
echo "$CTX" | grep -q 'Recent Activity Map' && pass "context emits Recent Activity Map" \
  || fail "context emits Recent Activity Map"

# The example vault's log uses the inline '**Goal:**' form.
if echo "$CTX" | grep -q 'Initialize the AGNT Procedural Memory system'; then
  pass "goal extracted from inline '**Goal:**' form"
else
  fail "goal extracted from inline '**Goal:**' form" "$(echo "$CTX" | tail -2 | tr '\n' ' ')"
fi

# Synthesize a heading-style log to cover the other format.
mkdir -p "$VAULT/JRNL/AGNT"
cat >"$VAULT/JRNL/AGNT/2099-01-01-0000.md" <<'LOG'
---
status: crystallized
---

# Session Log: 2099-01-01

## Goal
Verify heading style goal extraction works.

## Actions Taken
- None.
LOG
HEADING_CTX=$(bash scripts/agent-memory-context.sh 2>&1)
if echo "$HEADING_CTX" | grep -q 'Verify heading style goal extraction works'; then
  pass "goal extracted from '## Goal' heading form"
else
  fail "goal extracted from '## Goal' heading form" \
       "map was: $(echo "$HEADING_CTX" | grep '^| 2099' || echo '<no 2099 row in map>')"
fi
rm -f "$VAULT/JRNL/AGNT/2099-01-01-0000.md"

for hook in .codex/hooks/session-start.sh .claude/hooks/session-start.sh; do
  if bash "$hook" 2>/dev/null | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null; then
    pass "$hook emits valid SessionStart JSON"
  else
    fail "$hook emits valid SessionStart JSON"
  fi
done

# --- 5. Session compiler ----------------------------------------------------
section "5. Session compiler"

check "compile-sessions.sh handles no logs" \
  env AI_MEMORY_DRY_RUN=1 bash scripts/compile-sessions.sh 1

out=$(AI_MEMORY_HOST=bogus AI_MEMORY_DRY_RUN=1 bash scripts/compile-sessions.sh 1 2>&1)
echo "$out" | grep -q 'No session logs found' && pass "reports empty log set cleanly" \
  || fail "reports empty log set cleanly" "$out"

# Synthesize a Claude Code transcript and confirm it is extracted.
mkdir -p "$HOME/.claude/projects/-test"
cat >"$HOME/.claude/projects/-test/session.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"always use pytest for python tests"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Understood, pytest it is."}]}}
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"x","type":"tool_result","content":"noise"}]}}
JSONL
comp=$(AI_MEMORY_DRY_RUN=dump bash scripts/compile-sessions.sh 1 2>/dev/null)
echo "$comp" | grep -q '\[user\] always use pytest' && pass "extracts Claude user turns" \
  || fail "extracts Claude user turns"
echo "$comp" | grep -q '\[assistant\] Understood' && pass "extracts Claude assistant turns" \
  || fail "extracts Claude assistant turns"
echo "$comp" | grep -q 'tool_result' && fail "filters Claude tool_result noise" \
  || pass "filters Claude tool_result noise"

# Synthesize an OpenCode SQLite store and confirm it is extracted.
OCDB="$HOME/.local/share/opencode/opencode.db"
mkdir -p "$(dirname "$OCDB")"
NOW_MS=$(( $(date +%s) * 1000 ))
sqlite3 "$OCDB" "
  CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
  CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
  INSERT INTO message VALUES ('m1','s1',$NOW_MS,$NOW_MS,'{\"role\":\"user\"}');
  INSERT INTO part VALUES ('p1','m1','s1',$NOW_MS,$NOW_MS,'{\"type\":\"text\",\"text\":\"prefer vitest in this repo\"}');
" 2>/dev/null
comp=$(AI_MEMORY_DRY_RUN=dump bash scripts/compile-sessions.sh 1 2>/dev/null)
echo "$comp" | grep -q 'prefer vitest in this repo' && pass "extracts OpenCode SQLite turns" \
  || fail "extracts OpenCode SQLite turns"

out=$(AI_MEMORY_HOST=bogus bash scripts/compile-sessions.sh 1 2>&1)
echo "$out" | grep -q 'Unsupported AI_MEMORY_HOST' && pass "rejects unknown AI_MEMORY_HOST" \
  || fail "rejects unknown AI_MEMORY_HOST" "$out"

# --- 6. Migration script ----------------------------------------------------
section "6. Migration script"

printf 'legacy\n' >.gitattributes
echo '.gemini-obsidian/**/*.lance filter=lfs diff=lfs merge=lfs -text' >>.gitattributes
check "migrate-v2.sh runs non-interactively" bash scripts/migrate-v2.sh --yes

if grep -q '.obsidian-vault-mcp/' .gitattributes && ! grep -q '.gemini-obsidian/' .gitattributes; then
  pass "migrate-v2.sh rewrites LFS globs"
else
  fail "migrate-v2.sh rewrites LFS globs" "$(cat .gitattributes | tr '\n' ' ')"
fi

check "migrate-v2.sh is re-runnable" bash scripts/migrate-v2.sh --yes

# --- 7. Setup script dependency gates ---------------------------------------
section "7. Setup script dependency gates"

# Each setup script must fail fast with a clear message when its CLI is
# missing, rather than proceeding and leaving a half-configured host.
#
# Run with a PATH that has the core utilities but none of the agent CLIs, so
# the result is the same here and on a machine that has them installed.
STUB_BIN=$(mktemp -d)
for tool in bash sh env git jq node npx sed awk grep cat ls mkdir rm cp basename dirname tr head tail find chmod; do
  src=$(command -v "$tool" 2>/dev/null) && ln -sf "$src" "$STUB_BIN/$tool"
done

for h in claude codex gemini opencode; do
  out=$(env -i PATH="$STUB_BIN" HOME="$HOME" bash ".$h/setup-environment.sh" </dev/null 2>&1)
  if echo "$out" | grep -q "is required but not installed"; then
    pass ".$h/setup-environment.sh fails fast without its CLI"
  else
    fail ".$h/setup-environment.sh fails fast without its CLI" \
         "$(echo "$out" | tail -2 | tr '\n' ' ')"
  fi
done
rm -rf "$STUB_BIN"

# --- Summary ----------------------------------------------------------------
echo ""
echo "======================================================="
printf ' \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then
  printf '\033[31m%d failed\033[0m\n' "$FAIL"
  echo ""
  echo " Failures:"
  for n in "${FAILED_NAMES[@]}"; do echo "   - $n"; done
  echo "======================================================="
  exit 1
fi
printf '0 failed\n'
echo "======================================================="
