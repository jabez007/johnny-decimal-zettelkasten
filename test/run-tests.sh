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

# OpenCode has no tool allowlist, so each agent must deny the MCP namespace
# and re-allow only its own tools. Without this an agent inherits every tool
# the server exposes, including writes on a read-only agent.
oc_ok=1
for f in .opencode/agents/*.md; do
  grep -q '"obsidian-vault-mcp_\*": deny' "$f" || oc_ok=0
done
[ "$oc_ok" = 1 ] && pass "OpenCode agents deny the MCP namespace by default" \
  || fail "OpenCode agents deny the MCP namespace by default"

if grep -q '"obsidian-vault-mcp_obsidian_read_note": allow' .opencode/agents/librarian.md; then
  pass "OpenCode agents re-allow their declared MCP tools"
else
  fail "OpenCode agents re-allow their declared MCP tools"
fi

# OpenCode's edit permission must track the declared capabilities, not the
# readonly flag. Otherwise an agent that writes only through MCP gets working
# tree access in OpenCode while every other harness withholds its Write tool.
parity_ok=1
for src in .agents/agents/*.md; do
  n=$(basename "$src" .md)
  caps=$(grep '^capabilities:' "$src")
  oc_edit=$(grep -m1 '^  edit:' ".opencode/agents/$n.md" | awk '{print $2}')
  scope=$(grep -m1 '^write_scope:' "$src" || true)
  if echo "$caps" | grep -qE 'write|edit'; then
    # A scoped writer prompts instead of being granted outright.
    if [ -n "$scope" ]; then want=ask; else want=allow; fi
    cw_want=allow
  else
    want=deny; cw_want=deny
  fi
  [ "$oc_edit" = "$want" ] || { parity_ok=0; echo "       $n: capabilities imply edit:$want, OpenCode says $oc_edit"; }
  # Claude only lists Write when the capability is declared.
  if grep -q '^tools:.*Write' ".claude/agents/$n.md"; then cw=allow; else cw=deny; fi
  [ "$cw" = "$cw_want" ] || { parity_ok=0; echo "       $n: capabilities imply Write=$cw_want, Claude says $cw"; }
done
[ "$parity_ok" = 1 ] && pass "filesystem write permissions agree across harnesses" \
  || fail "filesystem write permissions agree across harnesses"

# The scaffolder creates notes through MCP and never through a shell. Its one
# filesystem write is Bases config, which must be declared as a write_scope.
sc=.agents/agents/vault-scaffolder.md
if grep -q '^mcp_tools:.*obsidian_create_note' "$sc" && ! grep -qE '^capabilities:.*bash' "$sc"; then
  pass "vault-scaffolder creates notes via MCP and has no shell"
else
  fail "vault-scaffolder creates notes via MCP and has no shell"
fi

# Any agent holding a filesystem write capability must declare what it is for.
scope_ok=1
for src in .agents/agents/*.md; do
  grep -qE '^capabilities:.*(write|edit)' "$src" || continue
  n=$(basename "$src" .md)
  # daily-reviewer writes freely by design; everything else must be scoped.
  [ "$n" = "daily-reviewer" ] && continue
  grep -q '^write_scope:' "$src" || { scope_ok=0; echo "       $n: has write but declares no write_scope"; }
done
[ "$scope_ok" = 1 ] && pass "scoped writers declare a write_scope" \
  || fail "scoped writers declare a write_scope"

# The declared scope must reach every harness body, since no harness can bound
# a write tool to a path pattern.
if grep -q '^write_scope:' "$sc"; then
  sc_ok=1
  for g in .claude/agents/vault-scaffolder.md .gemini/agents/vault-scaffolder.md \
           .opencode/agents/vault-scaffolder.md .codex/agents/vault-scaffolder.toml; do
    grep -q 'Filesystem Write Scope' "$g" || { sc_ok=0; echo "       missing scope section: $g"; }
  done
  [ "$sc_ok" = 1 ] && pass "write scope is stated in every generated harness copy" \
    || fail "write scope is stated in every generated harness copy"
fi

# An agent declared readonly must not hold a mutating MCP tool. The auditor
# reads untrusted note content, so a write capability there is a prompt
# injection path into the vault.
ro_ok=1
for src in .agents/agents/*.md; do
  grep -q '^readonly: true' "$src" || continue
  if grep -qE '^mcp_tools:.*(create_note|move_note|append_note|replace_in_note|replace_section|insert_at_heading|update_frontmatter)' "$src"; then
    ro_ok=0
    echo "       readonly agent with a write tool: $src"
  fi
done
[ "$ro_ok" = 1 ] && pass "read-only agents hold no mutating MCP tools" \
  || fail "read-only agents hold no mutating MCP tools"

# Every status an agent emits must be in the canonical enum. `redirect` was
# removed, so nothing may reintroduce an undocumented value.
if grep -rn 'status: redirect' .agents/ references/ >/dev/null 2>&1; then
  fail "no agent emits an undocumented status value" "found 'status: redirect'"
else
  pass "no agent emits an undocumented status value"
fi

# Merges no longer leave tombstones, so the cleaner must be able to find and
# repoint inbound links itself.
if grep -q 'obsidian_get_backlinks' .agents/agents/vault-cleaner.md \
   && grep -q 'obsidian_replace_in_note' .agents/agents/vault-cleaner.md; then
  pass "vault-cleaner can repoint inbound links on merge"
else
  fail "vault-cleaner can repoint inbound links on merge"
fi

# Frontmatter examples must use replaceable tokens. Prose placeholders are
# valid YAML: "entities: [List of 3-5 core concepts, people, or terms]" parses
# as three junk strings, and an agent copying the block writes them into the
# graph. entities/communities are exact-match rag_query filter keys, so junk
# there is not cosmetic.
python3 - <<'PY' && pass "frontmatter examples use valid tokens and scalar status" || fail "frontmatter examples use valid tokens and scalar status"
import glob, os, re, sys, yaml
root = os.environ.get("WORK_DIR", "/work/repo")
ALLOWED = {"distilled", "crystallized", "synthesized", "scaffolded"}
bad = []
srcs = glob.glob(os.path.join(root, ".agents/agents/*.md")) \
     + glob.glob(os.path.join(root, ".agents/skills/*/SKILL.md")) \
     + [os.path.join(root, "references/librarian/copilot-instructions.md")]
for f in srcs:
    for block in re.findall(r"```yaml\n(.*?)```", open(f).read(), re.S):
        try:
            d = yaml.safe_load(block.replace("---", "").strip())
        except Exception:
            continue
        if not isinstance(d, dict):
            continue
        for key in ("entities", "communities"):
            for v in (d.get(key) or []):
                if isinstance(v, str) and not v.startswith("<"):
                    bad.append(f"{os.path.basename(f)}: {key} -> {v!r}")
        # status must be a scalar. "status: [a|b|c]" is a YAML flow sequence,
        # so it writes a one-element list instead of one valid value.
        if "status" in d:
            st = d["status"]
            if not isinstance(st, str):
                bad.append(f"{os.path.basename(f)}: status is {type(st).__name__}, not a scalar -> {st!r}")
            elif not st.startswith("<") and st not in ALLOWED:
                bad.append(f"{os.path.basename(f)}: status -> {st!r} not in {sorted(ALLOWED)}")
if bad:
    print("; ".join(bad[:4])); sys.exit(1)
PY

# AC.00 is not a valid ID: 0 is reserved at every level and there is no
# category-level index. Policies may say it is invalid, never prescribe it.
if grep -rn 'AC\.00' .agents/ references/ | grep -qv 'not valid\|not a valid\|is invalid'; then
  fail "no policy prescribes AC.00 as a usable ID" \
       "$(grep -rn 'AC\.00' .agents/ references/ | grep -v 'not valid\|not a valid\|is invalid' | head -2 | tr '\n' ' ')"
else
  pass "no policy prescribes AC.00 as a usable ID"
fi

# Codex strips the prefix placeholder, so no generated text may end up saying
# "use X instead of X" or referencing an empty prefix.
if grep -q 'prefixed with ``' .codex/agents/*.toml; then
  fail "Codex agents have no empty-prefix artifact" \
       "$(grep -l 'prefixed with ``' .codex/agents/*.toml | tr '\n' ' ')"
else
  pass "Codex agents have no empty-prefix artifact"
fi

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

# Ask the running server what it actually exposes, then confirm every tool the
# agent policies grant still exists. This is what catches a tool being renamed
# or dropped in a future MCP release, rather than trusting the README.
TOOLS_JSON=$(mktemp)
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"harness","version":"1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  sleep 12
} | $MCP_CMD 2>/dev/null >"$TOOLS_JSON" || true

SERVER_TOOLS=$(jq -r 'select(.id==2) | .result.tools[].name' "$TOOLS_JSON" 2>/dev/null | sort)
if [ -z "$SERVER_TOOLS" ]; then
  fail "MCP server advertises its tool list" "no tools/list response"
else
  pass "MCP server advertises its tool list ($(wc -l <<<"$SERVER_TOOLS") tools)"

  GRANTED=$(grep -h '^mcp_tools:' "$WORK_DIR"/.agents/agents/*.md \
            | sed 's/mcp_tools: \[//; s/\]//; s/, /\n/g' | grep -v '^$' | sort -u)
  UNKNOWN=$(comm -23 <(echo "$GRANTED") <(echo "$SERVER_TOOLS"))
  [ -z "$UNKNOWN" ] && pass "every granted MCP tool exists on the server" \
    || fail "every granted MCP tool exists on the server" "unknown: $(echo "$UNKNOWN" | tr '\n' ' ')"

  # A body may only name a tool its own policy grants.
  body_ok=1
  for src in "$WORK_DIR"/.agents/agents/*.md; do
    g=$(grep '^mcp_tools:' "$src" | sed 's/mcp_tools: \[//; s/\]//; s/, /\n/g')
    for u in $(grep -oE '\{\{MCP_PREFIX\}\}obsidian_[a-z_]+' "$src" | sed 's/{{MCP_PREFIX}}//' | sort -u); do
      grep -qx "$u" <<<"$g" || { body_ok=0; echo "       $(basename "$src") uses ungranted $u"; }
    done
  done
  [ "$body_ok" = 1 ] && pass "no agent body references a tool it was not granted" \
    || fail "no agent body references a tool it was not granted"
fi
rm -f "$TOOLS_JSON"

if [ -n "${SKIP_RAG_INDEX:-}" ]; then
  echo "  SKIP RAG indexing (SKIP_RAG_INDEX set)"
else
  echo "  (indexing downloads the embedding model on first run; this is slow)"
  INDEX_LOG=$(mktemp); QUERY_LOG=$(mktemp)
  trap 'rm -f "$INDEX_LOG" "$QUERY_LOG"' EXIT
  if $MCP_CMD obsidian_rag_index --path "$VAULT" --workspace_path "$WORK_DIR" \
       --vault_id test_example --force_reindex true >"$INDEX_LOG" 2>&1; then
    pass "obsidian_rag_index --force_reindex true"
    if [ -d "$WORK_DIR/.obsidian-vault-mcp" ]; then
      pass "index written to .obsidian-vault-mcp/ (v2 storage name)"
    else
      fail "index written to .obsidian-vault-mcp/ (v2 storage name)" \
           "found: $(find "$WORK_DIR" -maxdepth 1 -name '.*obsidian*' -printf '%f ' 2>/dev/null)"
    fi
    if $MCP_CMD obsidian_rag_query --query "Johnny Decimal index" --path "$VAULT" \
         --workspace_path "$WORK_DIR" --vault_id test_example >"$QUERY_LOG" 2>&1; then
      pass "obsidian_rag_query returns results"
      if grep -q 'undefined' "$QUERY_LOG"; then
        fail "rag_query relevance score renders" "output contains 'undefined'"
      else
        pass "rag_query relevance score renders"
      fi
    else
      fail "obsidian_rag_query returns results" "$(tail -3 "$QUERY_LOG" | tr '\n' ' ')"
    fi
  else
    fail "obsidian_rag_index --force_reindex true" "$(tail -5 "$INDEX_LOG" | tr '\n' ' ')"
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

# A failing context script must still yield a diagnostic, not an empty context.
CTX_BACKUP=$(mktemp)
cp scripts/agent-memory-context.sh "$CTX_BACKUP"
printf '#!/bin/bash\necho "simulated failure" >&2\nexit 1\n' >scripts/agent-memory-context.sh
hook_ok=1
for hook in .codex/hooks/session-start.sh .claude/hooks/session-start.sh; do
  ctx=$(bash "$hook" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  [ -n "$ctx" ] || hook_ok=0
done
[ "$hook_ok" = 1 ] && pass "hooks degrade to a diagnostic when the context script fails" \
  || fail "hooks degrade to a diagnostic when the context script fails" "got an empty context"
mv "$CTX_BACKUP" scripts/agent-memory-context.sh

# The jq refresh branch must tolerate a SessionStart entry with no hooks array.
if echo '{"hooks":{"SessionStart":[{"matcher":"*"},{"matcher":"x","hooks":[{"name":"agent-memory-boot","command":"old"}]}]}}' \
   | jq --arg name "agent-memory-boot" --arg script "/new" '
       .hooks |= (. // {}) | .hooks.SessionStart |= (. // [])
       | if any(.hooks.SessionStart[]; (.hooks? // []) | any(.[]; .name == $name)) then
           .hooks.SessionStart |= map(
             if (.hooks | type) == "array" then
               .hooks |= map(if .name == $name then .command = $script else . end)
             else . end)
         else . end' >/dev/null 2>&1; then
  pass "hook registration tolerates entries without a hooks array"
else
  fail "hook registration tolerates entries without a hooks array"
fi

# --- 4b. Harness parity -----------------------------------------------------
section "4b. Harness parity"

# The four setup scripts are hand-maintained, so the generator cannot keep them
# aligned. These assert the contract they are all supposed to honour.
for h in claude codex gemini opencode; do
  f=".$h/setup-environment.sh"
  missing=""
  grep -q 'set -euo pipefail' "$f"                  || missing="$missing set-euo"
  grep -qE "for cmd in .*git.*jq.*node.*npx.*$h" "$f" || missing="$missing dep-check"
  grep -q 'configure-vault.sh' "$f"                 || missing="$missing configure-vault"
  grep -q 'sync-assets.sh' "$f"                     || missing="$missing sync-assets"
  grep -q 'MIGRATION.md' "$f"                       || missing="$missing reindex-warning"
  [ -z "$missing" ] && pass "$f honours the setup contract" \
    || fail "$f honours the setup contract" "missing:$missing"
done

# Every SessionStart hook must behave identically on both paths. The Gemini one
# is generated inside a heredoc, so it is extracted and executed the same way
# the setup script would write it. A degradation fix landed for Claude and
# Codex before Gemini once already; this is what catches that next time.
HOOK_DIR=$(mktemp -d)
CONTEXT_TARGET="$WORK_DIR/scripts/agent-memory-context.sh"
export CONTEXT_TARGET
sed -n '/^cat >"\$HOOK_SCRIPT" <<EOF$/,/^EOF$/p' .gemini/setup-environment.sh \
  | sed '1d;$d' >"$HOOK_DIR/raw"
if [ -s "$HOOK_DIR/raw" ]; then
  eval "cat <<EOF
$(cat "$HOOK_DIR/raw")
EOF" >"$HOOK_DIR/gemini-hook.sh"
  pass "Gemini hook is extractable from the setup heredoc"
else
  fail "Gemini hook is extractable from the setup heredoc"
fi

HOOKS=(".claude/hooks/session-start.sh" ".codex/hooks/session-start.sh" "$HOOK_DIR/gemini-hook.sh")

# Path 1: a working context script yields real content.
ok=1
for hk in "${HOOKS[@]}"; do
  [ -f "$hk" ] || { ok=0; echo "       missing hook: $hk"; continue; }
  ctx=$(bash "$hk" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  case "$ctx" in
    *"Agent Memory SOPs"*) ;;
    *) ok=0; echo "       $hk did not emit SOPs (got ${#ctx} chars)" ;;
  esac
done
[ "$ok" = 1 ] && pass "all SessionStart hooks emit SOPs on the success path" \
  || fail "all SessionStart hooks emit SOPs on the success path"

# Path 2: a failing context script must still yield a diagnostic, never an
# empty context and never a false claim of success.
CTX_SAVE=$(mktemp)
cp scripts/agent-memory-context.sh "$CTX_SAVE"
printf '#!/bin/bash\necho "simulated failure" >&2\nexit 1\n' >scripts/agent-memory-context.sh
ok=1
for hk in "${HOOKS[@]}"; do
  [ -f "$hk" ] || continue
  outj=$(bash "$hk" 2>/dev/null)
  ctx=$(echo "$outj" | jq -r '.hookSpecificOutput.additionalContext // ""')
  [ -n "$ctx" ] || { ok=0; echo "       $hk emitted an empty context on failure"; }
  # Gemini also carries a systemMessage; it must not claim success.
  msg=$(echo "$outj" | jq -r '.systemMessage // ""')
  case "$msg" in
    *restored*) ok=0; echo "       $hk claims 'restored' while the context failed" ;;
  esac
done
[ "$ok" = 1 ] && pass "all SessionStart hooks degrade honestly on failure" \
  || fail "all SessionStart hooks degrade honestly on failure"
cp "$CTX_SAVE" scripts/agent-memory-context.sh
rm -f "$CTX_SAVE"
rm -rf "$HOOK_DIR"

# --- 5. Session compiler ----------------------------------------------------
section "5. Session compiler"

check "compile-sessions.sh handles no logs" \
  env AI_MEMORY_DRY_RUN=1 bash scripts/compile-sessions.sh 1

# macOS and other BSD hosts expose date -j/-v rather than GNU date -d. Keep a
# stub first on PATH so this Linux-run suite also exercises that branch.
DATE_STUB_DIR=$(mktemp -d)
cat >"$DATE_STUB_DIR/date" <<'DATE_STUB'
#!/bin/bash
if [ "${1:-}" = "-d" ]; then
  exit 1
fi
case " $* " in
  *" -j -f %Y-%m-%d 1970-01-01 +%s "*) echo 0 ;;
  *" -v-1d +%s "*) echo 1700000000 ;;
  *" -j -f %Y-%m-%d 2026-08-01 +%s "*) echo 1785542400 ;;
  *" -j -v+1d -f %Y-%m-%d 2026-08-02 +%s "*) echo 1785801600 ;;
  *) exit 1 ;;
esac
DATE_STUB
chmod +x "$DATE_STUB_DIR/date"
check "compile-sessions.sh supports BSD relative dates" \
  env PATH="$DATE_STUB_DIR:$PATH" AI_MEMORY_DRY_RUN=1 bash scripts/compile-sessions.sh 1
check "compile-sessions.sh supports BSD date ranges" \
  env PATH="$DATE_STUB_DIR:$PATH" AI_MEMORY_DRY_RUN=1 bash scripts/compile-sessions.sh 2026-08-01 2026-08-02
rm -rf "$DATE_STUB_DIR"

# Actually execute the generated wrapper. Checking only that the file exists
# once let a broken repo-root expression ship: the wrapper resolved to two
# newline-joined paths and could not exec the compiler at all.
WRAPPER=.gemini/skills/librarian-vault-manager/scripts/compile-sessions.sh
out=$(AI_MEMORY_DRY_RUN=1 bash "$WRAPPER" 1 2>&1)
if echo "$out" | grep -q 'Scanning for agent CLI session logs'; then
  pass "generated wrapper execs the compiler"
else
  fail "generated wrapper execs the compiler" "$(echo "$out" | tail -1)"
fi

# The wrapper must resolve from its own location, not the caller's cwd.
out=$(cd / && AI_MEMORY_DRY_RUN=1 bash "$WORK_DIR/$WRAPPER" 1 2>&1)
if echo "$out" | grep -q 'Scanning for agent CLI session logs'; then
  pass "generated wrapper works from an unrelated cwd"
else
  fail "generated wrapper works from an unrelated cwd" "$(echo "$out" | tail -1)"
fi

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
  || fail "rejects unknown AI_MEMORY_HOST"

# A transcript holding only tool-call noise must not produce a payload of bare
# separators, which would look non-empty and invoke a reviewer on nothing.
rm -rf "$HOME/.claude/projects" "$HOME/.local/share/opencode"
mkdir -p "$HOME/.claude/projects/-noise"
echo '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"x","type":"tool_result","content":"noise"}]}}' \
  >"$HOME/.claude/projects/-noise/s.jsonl"
out=$(AI_MEMORY_DRY_RUN=1 bash scripts/compile-sessions.sh 1 2>&1)
if echo "$out" | grep -q 'No session logs found'; then
  pass "noise-only transcript reports no logs"
else
  fail "noise-only transcript reports no logs" "$(echo "$out" | tail -1)"
fi
rm -rf "$HOME/.claude/projects"

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

check "Codex setup uses marketplace upgrade" \
  grep -q 'codex plugin marketplace upgrade "$MARKETPLACE_NAME"' .codex/setup-environment.sh
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
