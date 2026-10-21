#!/bin/bash

# run-tests.sh
# Exercises the template's setup and migration scripts inside the container.
#
# Works on a copy of the read-only /repo mount, so the host working tree is
# never modified. Every check is non-interactive.

set -uo pipefail

REPO_SRC=${REPO_SRC:-/repo}
WORK_DIR=${WORK_DIR:-/work/repo}
MCP_CMD="npx -y @jabez007/obsidian-vault-mcp@2.1.0"

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
echo "  HOME    $HOME"

# --- Set up an isolated working copy ---------------------------------------
section "0. Working copy"

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

check "valid JSON: opencode.json" jq -e . opencode.json

check "opencode.json registers obsidian-vault-mcp" \
  jq -e '.mcp["obsidian-vault-mcp"].command | index("@jabez007/obsidian-vault-mcp@2.1.0")' opencode.json

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
    assert "hooks" not in cfg, "Codex config still registers hooks"
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
  for f in references/librarian/*.md; do
    cmp -s "$f" ".$h/skills/librarian-vault-manager/references/$(basename "$f")" || ok=0
  done
  [ "$ok" = 1 ] && pass "doctrine identical in .$h/skills/" || fail "doctrine identical in .$h/skills/"
done

# Promotion is the only route from a session into the vault, so every entry
# point that can file knowledge must point at it.
promo_ok=1
for f in AGENTS.md .agents/skills/librarian-vault-manager/SKILL.md \
         .agents/agents/librarian.md references/librarian/copilot-instructions.md; do
  grep -q 'knowledge-promotion.md' "$f" || { promo_ok=0; echo "       $f does not reference knowledge-promotion.md"; }
done
[ "$promo_ok" = 1 ] && pass "promotion doctrine is referenced from every entry point" \
  || fail "promotion doctrine is referenced from every entry point"

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

    # The Publish step of knowledge promotion, driven over MCP stdio the way an
    # agent calls it. The CLI cannot carry frontmatter: it reads any value that
    # starts with "--" as the next flag. An approved note is indexed on write
    # and found by the next query, and a second create at the same ID is
    # refused rather than overwritten.
    PROMO="LIFE/20-Personal Development/21-Learnings and Skills/LIFE.21.0F.md"
    PROMO_BODY=$'---\nentities: [harness-fixture, knowledge-promotion]\ncommunities: [LIFE.21]\nstatus: distilled\n---\n[[LIFE.00.00]]\n\n# Approved promotions are indexed on write\n\nThe quokka-lighthouse fixture proves that an approved note is searchable\nas soon as it is written.\n'
    promo_call() {
      jq -nc --argjson id "$1" --arg c "$2" --arg p "$PROMO" --arg v "$VAULT" --arg w "$WORK_DIR" \
        '{jsonrpc:"2.0", id:$id, method:"tools/call", params:{name:"obsidian_create_note",
          arguments:{file_path:$p, content:$c, vault_path:$v, workspace_path:$w, vault_id:"test_example"}}}'
    }
    PROMO_LOG=$(mktemp)
    # Each request waits for the server's reply to the one before, so the
    # duplicate create never races the first write and its re-index.
    promo_wait() {
      for _ in $(seq 1 60); do
        jq -se --argjson id "$1" 'any(.[]; .id==$id)' "$PROMO_LOG" >/dev/null 2>&1 && return
        sleep 1
      done
    }
    {
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"harness","version":"1"}}}'
      printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
      promo_call 2 "$PROMO_BODY"
      promo_wait 2
      promo_call 3 "replaced"
      promo_wait 3
    } | $MCP_CMD 2>/dev/null >"$PROMO_LOG" || true

    PROMO_HIT=$($MCP_CMD obsidian_rag_query --query "quokka-lighthouse fixture" --path "$VAULT" \
                  --workspace_path "$WORK_DIR" --vault_id test_example 2>/dev/null | grep '^File:' | head -1)
    if jq -se 'any(.[]; .id==2 and .result.isError != true)' "$PROMO_LOG" >/dev/null 2>&1 \
       && cmp -s <(printf '%s' "$PROMO_BODY") "$VAULT/$PROMO" \
       && [[ "$PROMO_HIT" == *LIFE.21.0F* ]]; then
      pass "promoted note is written and ranked first by rag_query"
    else
      fail "promoted note is written and ranked first by rag_query" "top hit: ${PROMO_HIT:-none}"
    fi
    if jq -se 'any(.[]; .id==3 and .result.isError == true)' "$PROMO_LOG" >/dev/null 2>&1 \
       && cmp -s <(printf '%s' "$PROMO_BODY") "$VAULT/$PROMO"; then
      pass "promotion refuses to overwrite an existing ID"
    else
      fail "promotion refuses to overwrite an existing ID"
    fi
    rm -f "$PROMO_LOG" "${VAULT:?}/${PROMO:?}"
  else
    fail "obsidian_rag_index --force_reindex true" "$(tail -5 "$INDEX_LOG" | tr '\n' ' ')"
  fi
fi

# --- 4. Agent memory is retired -------------------------------------------
section "4. Agent memory is retired"

# The vault no longer injects session context or asks agents to log sessions.
# Any of these files coming back means the coupling came back with it.
retired_ok=1
for f in scripts/agent-memory-context.sh scripts/compile-sessions.sh \
         .claude/hooks/session-start.sh .codex/hooks/session-start.sh \
         .claude/skills/librarian-vault-manager/scripts \
         .gemini/skills/librarian-vault-manager/scripts; do
  [ -e "$f" ] && { retired_ok=0; echo "       still present: $f"; }
done
[ "$retired_ok" = 1 ] && pass "retired hook, context, and compiler files are gone" \
  || fail "retired hook, context, and compiler files are gone"

if [ ! -f .claude/settings.json ] || ! jq -e '.hooks.SessionStart' .claude/settings.json >/dev/null 2>&1; then
  pass "Claude Code has no SessionStart hook"
else
  fail "Claude Code has no SessionStart hook"
fi

if grep -q 'hooks' .codex/config.toml; then
  fail "Codex config has no hooks"
else
  pass "Codex config has no hooks"
fi

if grep -qE 'SessionStart \+=|cat >"\$HOOK_SCRIPT"' .gemini/setup-environment.sh; then
  fail "Gemini setup installs no global hook"
else
  pass "Gemini setup installs no global hook"
fi

# The sample vault demonstrates the knowledge system only.
if [ -z "$(find vaults/example -path '*AGNT*' -print -quit)" ] \
   && ! grep -rq 'Agent Staff Report' vaults/example; then
  pass "sample vault carries no agent-memory content"
else
  fail "sample vault carries no agent-memory content"
fi

# Nothing that ships agent instructions may tell an agent to write session logs
# or procedural rules into the vault. The migration doctrine may name the
# legacy folders, so it is the one place they can appear.
if grep -rnE 'Shutdown Sequence|Boot Sequence|Recent Activity Map|Log the session to|compile-sessions' \
     AGENTS.md CLAUDE.md .agents references .claude .codex .gemini .opencode opencode.json 2>/dev/null; then
  fail "no agent instruction asks for session logging"
else
  pass "no agent instruction asks for session logging"
fi

# A memory provider is optional and configured outside this repository, so no
# script, setup step, or agent instruction may depend on one.
if grep -rniE 'hindsight' scripts .agents references .claude .codex .gemini .opencode \
     opencode.json AGENTS.md CLAUDE.md test/test-index-hooks.py 2>/dev/null; then
  fail "no script or agent asset references a memory provider"
else
  pass "no script or agent asset references a memory provider"
fi

# --- 4a. Legacy Gemini hook removal ---
HOOK_HOME=$(mktemp -d)
mkdir -p "$HOOK_HOME/.gemini/hooks"
printf '#!/bin/bash\n# Generated by johnny-decimal-zettelkasten/.gemini/setup-environment.sh.\n' \
  >"$HOOK_HOME/.gemini/hooks/agent-memory-boot.sh"
printf '#!/bin/bash\n# agent-memory-context.sh\n# Canonical Agent Memory boot context, shared by every hook.\n' \
  >"$HOOK_HOME/.gemini/hooks/agent-memory-context.sh"
printf 'keep me\n' >"$HOOK_HOME/.gemini/hooks/someone-elses-hook.sh"
cat >"$HOOK_HOME/.gemini/settings.json" <<'JSON'
{"theme":"dark","hooks":{"SessionStart":[
  {"matcher":"*"},
  {"matcher":"*","hooks":[{"name":"agent-memory-boot","type":"command","command":"/old"}]},
  {"matcher":"x","hooks":[{"name":"other","type":"command","command":"/o"}]}]}}
JSON
SETTINGS_BEFORE=$(sha256sum <"$HOOK_HOME/.gemini/settings.json")
HOME="$HOOK_HOME" bash scripts/migrate-agent-memory.sh legacy-hooks >/dev/null 2>&1
if [ "$(sha256sum <"$HOOK_HOME/.gemini/settings.json")" = "$SETTINGS_BEFORE" ] \
   && [ -f "$HOOK_HOME/.gemini/hooks/agent-memory-boot.sh" ]; then
  pass "legacy-hooks is a dry run without --apply"
else
  fail "legacy-hooks is a dry run without --apply"
fi
HOME="$HOOK_HOME" bash scripts/migrate-agent-memory.sh legacy-hooks --apply >/dev/null 2>&1
if jq -e '[.hooks.SessionStart[]?.hooks[]? | select(.name == "agent-memory-boot")] | length == 0' \
     "$HOOK_HOME/.gemini/settings.json" >/dev/null \
   && jq -e '.theme == "dark" and ([.hooks.SessionStart[]?.hooks[]? | select(.name == "other")] | length == 1)' \
     "$HOOK_HOME/.gemini/settings.json" >/dev/null \
   && [ -f "$HOOK_HOME/.gemini/settings.json.agent-memory-backup" ]; then
  pass "legacy-hooks removes only the retired registration and keeps a backup"
else
  fail "legacy-hooks removes only the retired registration and keeps a backup" \
       "$(tr -d '\n' <"$HOOK_HOME/.gemini/settings.json")"
fi
if [ ! -e "$HOOK_HOME/.gemini/hooks/agent-memory-boot.sh" ] \
   && [ ! -e "$HOOK_HOME/.gemini/hooks/agent-memory-context.sh" ] \
   && [ -f "$HOOK_HOME/.gemini/hooks/someone-elses-hook.sh" ]; then
  pass "legacy-hooks deletes only the files the old setup generated"
else
  fail "legacy-hooks deletes only the files the old setup generated"
fi
rm -rf "$HOOK_HOME"

# --- 4b. Legacy content migration ---
# A synthetic vault with every legacy shape: rules, a session log with a
# credential-shaped line, a Base, a human daily note that embeds the log, and a
# curated note that must not move.
MIG=$(mktemp -d)
MV="$MIG/repo/vaults/demo"
mkdir -p "$MV/AGNT/00-IDX" "$MV/AGNT/10-Procedural_Rules/11-Coding" "$MV/JRNL/AGNT" \
         "$MV/JRNL/2026/04" "$MV/_SYS" "$MV/LIFE/00-IDX" "$MV/LIFE/20-Personal Development/21-Learnings"
printf '[[00.00]]\n\n# AGNT System Index\n' >"$MV/AGNT/00-IDX/AGNT.00.00.md"
cat >"$MV/AGNT/10-Procedural_Rules/11-Coding/AGNT.11.01-Pytest-is-preferred.md" <<'NOTE'
---
entities: [pytest]
communities: [Agent Procedural Memory]
status: crystallized
---
[[AGNT.00.00]]

# AGNT.11.01 Pytest is preferred
NOTE
cat >"$MV/JRNL/AGNT/2026-04-24-1500.md" <<'NOTE'
# Session log

**Goal:** Set up the demo vault.

api_key = example-not-a-real-key
NOTE
printf 'filters:\n  and:\n    - file.folder.contains("AGNT")\n' >"$MV/_SYS/JDEX_AGNT.base"
cat >"$MV/JRNL/2026/04/2026-04-24.md" <<'NOTE'
# Friday, April 24, 2026

## Log

- Wrote about testing.
- ![[JRNL/AGNT/2026-04-24-1500#Goal]]
NOTE
cat >"$MV/LIFE/20-Personal Development/21-Learnings/LIFE.21.01-Tests-document-intent.md" <<'NOTE'
---
entities: [testing]
communities: [Learnings]
status: distilled
---
[[LIFE.00.00]]

# Tests document intent
NOTE
(cd "$MIG/repo" && git init -q . && git config user.email t@example.com && git config user.name T \
  && git add -A && git commit -qm base)
MIGRATE="$WORK_DIR/scripts/migrate-agent-memory.sh"
tree_sum() { (cd "$MV" && find . -type f -not -path './.archive/*' | LC_ALL=C sort | while IFS= read -r f; do sha256sum "$f"; done | sha256sum); }
# Content hashes of every tracked file, optionally ignoring one blob.
blob_sum() { git -C "$MIG/repo" ls-files -s | awk -v skip="${1:-}" '$2 != skip {print $2}' | LC_ALL=C sort | sha256sum; }
BASE_TREE=$(tree_sum)
BASE_BLOBS=$(blob_sum)
DAILY_SUM=$(sha256sum <"$MV/JRNL/2026/04/2026-04-24.md")
LIFE_SUM=$(sha256sum <"$MV/LIFE/20-Personal Development/21-Learnings/LIFE.21.01-Tests-document-intent.md")

INV=$(HOME="$MIG" bash "$MIGRATE" inventory --vault "$MV" 2>&1)
if echo "$INV" | grep -q 'Procedural rules (AGNT/): 1' \
   && echo "$INV" | grep -q 'Session logs (JRNL/AGNT/): 1' \
   && echo "$INV" | grep -q 'JRNL/AGNT/2026-04-24-1500.md <- JRNL/2026/04/2026-04-24.md' \
   && echo "$INV" | grep -q 'Possible credentials or private data: 1'; then
  pass "inventory classifies rules, logs, inbound links, and credentials"
else
  fail "inventory classifies rules, logs, inbound links, and credentials" "$(echo "$INV" | head -20 | tr '\n' ' ')"
fi
TSV=$(HOME="$MIG" bash "$MIGRATE" inventory --vault "$MV" --format tsv 2>&1)
[ "$(echo "$TSV" | head -1 | cut -f1-3)" = "$(printf 'path\tkind\tgit_state')" ] && [ "$(echo "$TSV" | wc -l)" -eq 5 ] \
  && pass "inventory --format tsv emits one row per legacy file" \
  || fail "inventory --format tsv emits one row per legacy file" "$(echo "$TSV" | tr '\n' '|')"

HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" >/dev/null 2>&1
rc=$?
[ "$(tree_sum)" = "$BASE_TREE" ] && [ -z "$(git -C "$MIG/repo" status --porcelain)" ] \
  && pass "inventory and archive dry run change nothing" \
  || fail "inventory and archive dry run change nothing"
[ "$rc" = 2 ] && pass "archive refuses while curated notes link to legacy content" \
  || fail "archive refuses while curated notes link to legacy content" "exit $rc"

echo "draft" >"$MV/JRNL/AGNT/2026-04-25-0900.md"
HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --apply --allow-inbound-links >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && [ -f "$MV/JRNL/AGNT/2026-04-24-1500.md" ] \
  && pass "archive refuses untracked legacy files" \
  || fail "archive refuses untracked legacy files" "exit $rc"
rm -f "$MV/JRNL/AGNT/2026-04-25-0900.md"

HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --scope logs --apply --allow-inbound-links >/dev/null 2>&1
if [ ! -e "$MV/JRNL/AGNT" ] && [ -f "$MV/.archive/agent-memory/JRNL/AGNT/2026-04-24-1500.md" ] \
   && [ -d "$MV/AGNT" ]; then
  pass "archive --scope logs moves only session logs"
else
  fail "archive --scope logs moves only session logs"
fi
(cd "$MIG/repo" && git commit -qm "archive logs")
HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --scope rules --apply >/dev/null 2>&1
if [ ! -e "$MV/AGNT" ] && [ ! -e "$MV/_SYS/JDEX_AGNT.base" ] \
   && git -C "$MIG/repo" diff --cached --name-status | grep -q '^R100'; then
  pass "archive --scope rules moves rules with git mv"
else
  fail "archive --scope rules moves rules with git mv"
fi
(cd "$MIG/repo" && git commit -qm "archive rules")

if [ "$(sha256sum <"$MV/JRNL/2026/04/2026-04-24.md")" = "$DAILY_SUM" ] \
   && [ "$(sha256sum <"$MV/LIFE/20-Personal Development/21-Learnings/LIFE.21.01-Tests-document-intent.md")" = "$LIFE_SUM" ]; then
  pass "personal journals and curated notes are untouched by the archive"
else
  fail "personal journals and curated notes are untouched by the archive"
fi
MANIFEST_BLOB=$(git -C "$MIG/repo" rev-parse HEAD:vaults/demo/.archive/agent-memory/MANIFEST.tsv)
[ "$(blob_sum "$MANIFEST_BLOB")" = "$BASE_BLOBS" ] \
  && pass "every archived file keeps identical content" \
  || fail "every archived file keeps identical content"

# Hidden paths are outside the MCP's index and Obsidian's file list.
if [ -z "$(cd "$MV" && find . -mindepth 1 -name '.*' -prune -o -path './AGNT/*' -print -o -path './JRNL/AGNT/*' -print)" ]; then
  pass "no legacy note remains on an indexed path"
else
  fail "no legacy note remains on an indexed path"
fi

HOME="$MIG" bash "$MIGRATE" restore --vault "$MV" --apply >/dev/null 2>&1
if [ "$(tree_sum)" = "$BASE_TREE" ] && [ ! -e "$MV/.archive" ] \
   && [ -z "$(git -C "$MIG/repo" diff --cached --stat HEAD~2)" ]; then
  pass "restore returns the vault to its original tree"
else
  fail "restore returns the vault to its original tree" "$(git -C "$MIG/repo" status --short | head -3 | tr '\n' ' ')"
fi
rm -rf "$MIG"

# --- 5. Harness parity -----------------------------------------------------
section "5. Harness parity"

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

# --- 6. Migration script ----------------------------------------------------
section "6. v2 migration script"

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

section "8. Index snapshot hooks"
if [ -z "${MCP_SNAPSHOT_RELEASE:-}" ]; then
  MCP_EXECUTABLE=$(npx --yes --package=@jabez007/obsidian-vault-mcp@2.1.0 -c 'command -v obsidian-vault-mcp')
  MCP_SNAPSHOT_RELEASE=$(node -e 'const fs = require("fs"), p = require("path"); console.log(p.dirname(p.dirname(fs.realpathSync(process.argv[1]))))' "$MCP_EXECUTABLE")
fi
if [ -f "$MCP_SNAPSHOT_RELEASE/package.json" ]; then
  check "snapshot hooks and published MCP round trip" \
    env MCP_SNAPSHOT_RELEASE="$MCP_SNAPSHOT_RELEASE" python3 test/test-index-hooks.py
else
  fail "resolve published MCP for snapshot round trip" "$MCP_SNAPSHOT_RELEASE"
fi

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
