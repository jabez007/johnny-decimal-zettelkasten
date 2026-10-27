#!/bin/bash

# run-tests.sh
# Exercises the template's setup and migration scripts inside the container.
#
# Works on a copy of the read-only /repo mount, so the host working tree is
# never modified. Every check is non-interactive.

set -uo pipefail

REPO_SRC=${REPO_SRC:-/repo}
WORK_DIR=${WORK_DIR:-/work/repo}
MCP_CMD="npx -y @jabez007/obsidian-vault-mcp@2.3.0"

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

mapfile -t SH_FILES < <(find . -name '*.sh' -not -path './config/*')
check "shellcheck (${#SH_FILES[@]} scripts)" shellcheck --severity=warning "${SH_FILES[@]}"

check "valid JSON: opencode.json" jq -e . opencode.json

check "opencode.json registers obsidian-vault-mcp" \
  jq -e '.mcp["obsidian-vault-mcp"].command | index("@jabez007/obsidian-vault-mcp@2.3.0")' opencode.json

# Codex finds each .codex/agents/*.toml by its name field, with no registry.
python3 - <<'PY' && pass "Codex agent files parse and match their filenames" || fail "Codex agent files parse and match their filenames"
import tomllib, glob, os, sys
root = os.environ.get("WORK_DIR", "/work/repo")
try:
    for f in glob.glob(os.path.join(root, ".codex/agents/*.toml")):
        agent = tomllib.load(open(f, "rb"))
        for key in ("name", "description", "developer_instructions"):
            assert agent.get(key), f"{os.path.basename(f)} has no {key}"
        stem = os.path.basename(f)[:-len(".toml")]
        assert agent["name"] == stem, f"{stem}.toml names {agent['name']}"
except Exception as e:
    print(e); sys.exit(1)
PY

# Claude Code reads CLAUDE.md instead of AGENTS.md, and Gemini CLI reads
# GEMINI.md unless its settings name another file. Both must load AGENTS.md.
check "CLAUDE.md imports AGENTS.md" grep -qx '@AGENTS.md' CLAUDE.md
check "Gemini settings load AGENTS.md" \
  jq -e '.context.fileName | index("AGENTS.md")' .gemini/settings.json

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

# An upgrade must preserve the vault selected by the legacy backend. Falling
# back to the sample vault would write a valid but surprising v2 config.
#
# configure_with_legacy_vault NAME|outside runs configure-vault.sh with no
# input, in a fresh HOME whose legacy config names vaults/NAME or a vault
# outside vaults/. Setup registers the vault and installs Git hooks, so it runs
# in a scratch copy that later sections never see. Snapshot installation is off
# there, so another vault's committed snapshot (#20) cannot fail the check.
configure_with_legacy_vault() {
  local scratch vault
  scratch=$(mktemp -d)
  cp -r "$WORK_DIR" "$scratch/repo"
  git -C "$scratch/repo" config obsidian.snapshotInstall off
  mkdir -p "$scratch/home" "$scratch/outside"
  case $1 in
    outside) vault="$scratch/outside" ;;
    *) vault="$scratch/repo/vaults/$1/"; mkdir -p "$vault" ;;
  esac
  jq -n --arg vault "$vault" --arg workspace "$scratch/repo" \
    '{vault_path: $vault, workspace_path: $workspace, vault_id: "test_existing"}' \
    >"$scratch/home/.gemini-obsidian.config.json"
  (cd "$scratch/repo" && HOME="$scratch/home" MCP_CMD=true bash scripts/configure-vault.sh </dev/null 2>&1)
  rm -rf "$scratch"
}

# The name is not a slug, so slugifying it would select a new vaults/my-vault.
out=$(configure_with_legacy_vault My_Vault)
if echo "$out" | grep -q "Vault configured: .*/repo/vaults/My_Vault "; then
  pass "configure-vault preserves the legacy configured vault by default"
else
  fail "configure-vault preserves the legacy configured vault by default" \
    "$(echo "$out" | tail -3 | tr '\n' ' ')"
fi

# This name has no ASCII letter or digit, so it slugifies to nothing.
out=$(configure_with_legacy_vault 日本)
if echo "$out" | grep -q "Vault configured: .*/repo/vaults/日本 (id: repo_vault-[0-9]*)"; then
  pass "configure-vault keeps a configured vault whose name has no slug"
else
  fail "configure-vault keeps a configured vault whose name has no slug" \
    "$(echo "$out" | tail -3 | tr '\n' ' ')"
fi

out=$(configure_with_legacy_vault outside)
if echo "$out" | grep -q "Not offering .*/outside from .*gemini-obsidian.config.json" \
  && echo "$out" | grep -q "Vault configured: .*/repo/vaults/example "; then
  pass "configure-vault reports a configured vault it will not offer"
else
  fail "configure-vault reports a configured vault it will not offer" \
    "$(echo "$out" | tail -3 | tr '\n' ' ')"
fi

# Claude Code is the one harness that does not read .agents/skills/. Its copy
# is the canonical skill plus a banner and a blank line after the frontmatter.
if cmp -s <(cat -s .agents/skills/librarian-vault-manager/SKILL.md) \
     <(sed '/^<!-- GENERATED FILE/,/-->$/d' .claude/skills/librarian-vault-manager/SKILL.md | cat -s); then
  pass "Claude skill copy matches the canonical skill"
else
  fail "Claude skill copy matches the canonical skill"
fi

# Promotion is the only route from a session into the vault, so every entry
# point that can file knowledge must point at it.
promo_ok=1
for f in AGENTS.md .agents/skills/librarian-vault-manager/SKILL.md \
         .agents/agents/librarian.md references/librarian/copilot-instructions.md; do
  grep -q 'knowledge-promotion.md' "$f" || { promo_ok=0; echo "       $f does not reference knowledge-promotion.md"; }
done
[ "$promo_ok" = 1 ] && pass "promotion doctrine is referenced from every entry point" \
  || fail "promotion doctrine is referenced from every entry point"

# AGENTS.md promises the same eight specialists in every harness. OpenCode
# names an agent by its filename; the others read a name field.
EXPECTED_AGENTS="daily-reviewer
flashcard-generator
librarian
source-distiller
vault-auditor
vault-cleaner
vault-scaffolder
vault-synthesizer"
for d in .agents/agents .claude/agents .gemini/agents .opencode/agents .codex/agents; do
  found=$(find "$d" -type f -exec basename {} \; | sed 's/\.[^.]*$//' | sort)
  [ "$found" = "$EXPECTED_AGENTS" ] && pass "$d holds the eight specialists" \
    || fail "$d holds the eight specialists" "found: $(tr '\n' ' ' <<<"$found")"
done

name_ok=1
for f in .agents/agents/*.md .claude/agents/*.md .gemini/agents/*.md; do
  [ "$(sed -n 's/^name: //p' "$f" | head -1)" = "$(basename "$f" .md)" ] \
    || { name_ok=0; echo "       $f has a name field that differs from its filename"; }
done
[ "$name_ok" = 1 ] && pass "agent name fields match their filenames" \
  || fail "agent name fields match their filenames"

if grep -rq '{{MCP_PREFIX}}' .claude .gemini .opencode .codex 2>/dev/null; then
  fail "no unsubstituted {{MCP_PREFIX}} in generated output"
else
  pass "no unsubstituted {{MCP_PREFIX}} in generated output"
fi


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
  $MCP_CMD obsidian_list_notes --vault_path "$VAULT"

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

# A harness drops a granted tool whose name it does not recognize, so each
# generated prefix must match the name the harness gives the server's tools.
# The manifests that set those names ship in the MCP repository, not on npm.
MCP_VERSION=${MCP_CMD##*@}
MCP_RAW="https://raw.githubusercontent.com/jabez007/obsidian-vault-mcp/v$MCP_VERSION"
if CLAUDE_PLUGIN=$(curl -fsSL "$MCP_RAW/.claude-plugin/plugin.json") \
   && GEMINI_EXT=$(curl -fsSL "$MCP_RAW/gemini-extension.json"); then
  claude_server=$(jq -r '.mcpServers | keys[0]' <<<"$CLAUDE_PLUGIN")
  claude_prefix="mcp__plugin_$(jq -r .name <<<"$CLAUDE_PLUGIN")_${claude_server}__"
  gemini_prefix="mcp_$(jq -r '.mcpServers | keys[0]' <<<"$GEMINI_EXT")_"
  opencode_prefix="$(jq -r '.mcp | keys[0]' opencode.json)_"
  prefix_ok=1
  # Every agent must keep every MCP tool its canonical policy grants.
  for src in .agents/agents/*.md; do
    n=$(basename "$src" .md)
    claude_tools=$(sed -n 's/^tools: //p' ".claude/agents/$n.md" | tr ',' '\n' | sed 's/^ *//')
    for tool in $(sed -n 's/^mcp_tools: \[\(.*\)\]/\1/p' "$src" | tr -d ','); do
      grep -qxF "$claude_prefix$tool" <<<"$claude_tools" \
        || { prefix_ok=0; echo "       .claude/agents/$n.md lacks $claude_prefix$tool"; }
      grep -qxF "  - $gemini_prefix$tool" ".gemini/agents/$n.md" \
        || { prefix_ok=0; echo "       .gemini/agents/$n.md lacks $gemini_prefix$tool"; }
      grep -qF "\"$opencode_prefix$tool\": allow" ".opencode/agents/$n.md" \
        || { prefix_ok=0; echo "       .opencode/agents/$n.md lacks $opencode_prefix$tool"; }
    done
  done
  [ "$prefix_ok" = 1 ] && pass "generated MCP tool names match each harness's install" \
    || fail "generated MCP tool names match each harness's install"
else
  fail "generated MCP tool names match each harness's install" "cannot fetch manifests at v$MCP_VERSION"
fi

if [ -n "${SKIP_RAG_INDEX:-}" ]; then
  echo "  SKIP RAG indexing (SKIP_RAG_INDEX set)"
else
  echo "  (indexing downloads the embedding model on first run; this is slow)"
  INDEX_LOG=$(mktemp); QUERY_LOG=$(mktemp)
  trap 'rm -f "$INDEX_LOG" "$QUERY_LOG"' EXIT
  if $MCP_CMD obsidian_rag_index --vault_path "$VAULT" --workspace_path "$WORK_DIR" \
       --vault_id test_example --force_reindex true >"$INDEX_LOG" 2>&1; then
    pass "obsidian_rag_index --force_reindex true"
    if [ -d "$WORK_DIR/.obsidian-vault-mcp" ]; then
      pass "index written to .obsidian-vault-mcp/ (v2 storage name)"
    else
      fail "index written to .obsidian-vault-mcp/ (v2 storage name)" \
           "found: $(find "$WORK_DIR" -maxdepth 1 -name '.*obsidian*' -printf '%f ' 2>/dev/null)"
    fi
    if $MCP_CMD obsidian_rag_query --query "Johnny Decimal index" --vault_path "$VAULT" \
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
      return 1
    }
    # A wait that times out ends the input, so no later request goes out
    # before the server has answered the one before it.
    {
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"harness","version":"1"}}}'
      printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
      promo_call 2 "$PROMO_BODY"
      promo_wait 2 || exit
      promo_call 3 "replaced"
      promo_wait 3 || exit
    } | $MCP_CMD 2>/dev/null >"$PROMO_LOG" || true

    PROMO_HIT=$($MCP_CMD obsidian_rag_query --query "quokka-lighthouse fixture" --vault_path "$VAULT" \
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

if grep -qs 'hooks' .codex/config.toml; then
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
# A synthetic vault with every legacy shape: rules, a clean session log, a
# session log with a credential-shaped line, a log Git never tracked, a Base, a
# human daily note that embeds a log, and a curated note that must not move.
MIG=$(mktemp -d)
MV="$MIG/repo/vaults/demo"
PRIV="$MIG/private/demo"
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
printf '# Session log\n\n**Goal:** Sketch the demo vault.\n' >"$MV/JRNL/AGNT/2026-04-23-1000.md"
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
BASE_COMMIT=$(git -C "$MIG/repo" rev-parse HEAD)
printf '# Session log\n\nA private client conversation.\n' >"$MV/JRNL/AGNT/2026-04-25-0900.md"
DRAFT_BLOB=$(git -C "$MIG/repo" hash-object "$MV/JRNL/AGNT/2026-04-25-0900.md")
SECRET_BLOB=$(git -C "$MIG/repo" rev-parse HEAD:vaults/demo/JRNL/AGNT/2026-04-24-1500.md)
MIGRATE="$WORK_DIR/scripts/migrate-agent-memory.sh"
tree_sum() { (cd "$MV" && find . -type f -not -path './.archive/*' | LC_ALL=C sort | while IFS= read -r f; do sha256sum "$f"; done | sha256sum); }
# Content hashes of every tracked file, ignoring the blobs named as arguments.
blob_sum() { git -C "$MIG/repo" ls-files -s | awk -v skip=" $* " 'index(skip, " " $2 " ") == 0 {print $2}' | LC_ALL=C sort | sha256sum; }
BASE_TREE=$(tree_sum)
BASE_STATUS=$(git -C "$MIG/repo" status --porcelain)
DAILY_SUM=$(sha256sum <"$MV/JRNL/2026/04/2026-04-24.md")
LIFE_SUM=$(sha256sum <"$MV/LIFE/20-Personal Development/21-Learnings/LIFE.21.01-Tests-document-intent.md")

INV=$(HOME="$MIG" bash "$MIGRATE" inventory --vault "$MV" 2>&1)
if echo "$INV" | grep -q 'Procedural rules (AGNT/): 1' \
   && echo "$INV" | grep -q 'Session logs (JRNL/AGNT/): 3' \
   && echo "$INV" | grep -q 'JRNL/AGNT/2026-04-24-1500.md <- JRNL/2026/04/2026-04-24.md' \
   && echo "$INV" | grep -q 'Possible credentials or private data: 1' \
   && echo "$INV" | grep -q 'Bound for the private archive, outside Git: 2' \
   && ! echo "$INV" | grep -q 'Commit these before archiving'; then
  pass "inventory classifies rules, logs, inbound links, credentials, and private files"
else
  fail "inventory classifies rules, logs, inbound links, credentials, and private files" "$(echo "$INV" | head -20 | tr '\n' ' ')"
fi
TSV=$(HOME="$MIG" bash "$MIGRATE" inventory --vault "$MV" --format tsv 2>&1)
[ "$(echo "$TSV" | head -1 | cut -f1-3)" = "$(printf 'path\tkind\tgit_state')" ] && [ "$(echo "$TSV" | wc -l)" -eq 7 ] \
  && echo "$TSV" | awk -F'\t' '$1 == "JRNL/AGNT/2026-04-25-0900.md" && $3 == "untracked" && $6 == "private:untracked"' | grep -q . \
  && pass "inventory --format tsv emits one row per legacy file with its destination" \
  || fail "inventory --format tsv emits one row per legacy file with its destination" "$(echo "$TSV" | tr '\n' '|')"

HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --private-dir "$PRIV" >/dev/null 2>&1
rc=$?
[ "$(tree_sum)" = "$BASE_TREE" ] && [ "$(git -C "$MIG/repo" status --porcelain)" = "$BASE_STATUS" ] \
  && [ ! -e "$MIG/private" ] \
  && pass "inventory and archive dry run change nothing" \
  || fail "inventory and archive dry run change nothing"
[ "$rc" = 2 ] && pass "archive refuses while curated notes link to legacy content" \
  || fail "archive refuses while curated notes link to legacy content" "exit $rc"

OUT=$(HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --apply --allow-inbound-links 2>&1)
rc=$?
[ "$rc" = 2 ] && [ "$(tree_sum)" = "$BASE_TREE" ] && echo "$OUT" | grep -q 'no --private-dir' \
  && pass "archive refuses files that must leave Git when no --private-dir is given" \
  || fail "archive refuses files that must leave Git when no --private-dir is given" "exit $rc"

HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --apply --allow-inbound-links --yes \
  --private-dir "$MIG/repo/agent-archive" >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && [ "$(tree_sum)" = "$BASE_TREE" ] && [ ! -e "$MIG/repo/agent-archive" ] \
  && pass "archive refuses a --private-dir inside a Git repository" \
  || fail "archive refuses a --private-dir inside a Git repository" "exit $rc"

OUT=$(HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --private-dir "$PRIV" --private AGNT \
  --allow-inbound-links 2>&1)
echo "$OUT" | grep -qF '[requested] AGNT/00-IDX/AGNT.00.00.md' \
  && echo "$OUT" | grep -qF '[untracked] JRNL/AGNT/2026-04-25-0900.md' \
  && echo "$OUT" | grep -qF '[sensitive] JRNL/AGNT/2026-04-24-1500.md' \
  && pass "archive --private sends a requested folder to the private archive" \
  || fail "archive --private sends a requested folder to the private archive" "$(echo "$OUT" | tr '\n' '|')"

# A folder name in the middle of a legacy path, or an empty value, matches
# nothing that private_reason would send to the private archive.
rcs=""
for p in 00-IDX ""; do
  HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --private-dir "$PRIV" --private "$p" \
    --allow-inbound-links >/dev/null 2>&1
  rcs="$rcs $?"
done
[ "$rcs" = " 1 1" ] && [ "$(tree_sum)" = "$BASE_TREE" ] \
  && pass "archive --private accepts only a vault-relative path prefix" \
  || fail "archive --private accepts only a vault-relative path prefix" "exits:$rcs"

HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --scope logs --apply --allow-inbound-links \
  --private-dir "$PRIV" </dev/null >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && [ "$(tree_sum)" = "$BASE_TREE" ] && [ ! -e "$MIG/private" ] \
  && pass "moving files out of Git needs explicit confirmation" \
  || fail "moving files out of Git needs explicit confirmation" "exit $rc"

HOME="$MIG" bash "$MIGRATE" archive --vault "$MV" --scope logs --apply --allow-inbound-links \
  --private-dir "$PRIV" --yes >/dev/null 2>&1
if [ ! -e "$MV/JRNL/AGNT" ] && [ -d "$MV/AGNT" ] \
   && [ -f "$MV/.archive/agent-memory/JRNL/AGNT/2026-04-23-1000.md" ] \
   && [ ! -e "$MV/.archive/agent-memory/JRNL/AGNT/2026-04-24-1500.md" ] \
   && [ -f "$PRIV/JRNL/AGNT/2026-04-24-1500.md" ] && [ -f "$PRIV/JRNL/AGNT/2026-04-25-0900.md" ]; then
  pass "archive --scope logs keeps clean logs in Git and moves the rest to the private archive"
else
  fail "archive --scope logs keeps clean logs in Git and moves the rest to the private archive"
fi
[ "$(stat -c %a "$PRIV" 2>/dev/null || stat -f %Lp "$PRIV")" = 700 ] \
  && (cd "$PRIV" && awk -F'\t' '$1 == "file" { print $2 "  " $5 }' PRIVATE-MANIFEST.tsv | sha256sum -c --quiet) \
  && pass "private archive is owner-only and matches its checksums" \
  || fail "private archive is owner-only and matches its checksums"
(cd "$MIG/repo" && git commit -qm "archive logs")
if ! git -C "$MIG/repo" cat-file -e "$DRAFT_BLOB" 2>/dev/null \
   && ! git -C "$MIG/repo" ls-tree -r HEAD | grep -q -e "$SECRET_BLOB" -e '2026-04-25-0900' \
   && ! git -C "$MIG/repo" ls-tree -r HEAD --name-only | grep -q 'agent-archive\|private'; then
  pass "untracked and credential-shaped logs never enter a commit"
else
  fail "untracked and credential-shaped logs never enter a commit"
fi

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
[ "$(blob_sum "$MANIFEST_BLOB")" = "$(git -C "$MIG/repo" ls-tree -r HEAD~2 | awk -v s="$SECRET_BLOB" '$3 != s {print $3}' | LC_ALL=C sort | sha256sum)" ] \
  && pass "every file kept in Git keeps identical content" \
  || fail "every file kept in Git keeps identical content"

# Hidden paths are outside the MCP's index and Obsidian's file list.
if [ -z "$(cd "$MV" && find . -mindepth 1 -name '.*' -prune -o -path './AGNT/*' -print -o -path './JRNL/AGNT/*' -print)" ]; then
  pass "no legacy note remains on an indexed path"
else
  fail "no legacy note remains on an indexed path"
fi

HOME="$MIG" bash "$MIGRATE" restore --vault "$MV" --private-dir "$PRIV" --apply >/dev/null 2>&1
git -C "$MIG/repo" add -- vaults/demo/JRNL/AGNT/2026-04-24-1500.md
if [ "$(tree_sum)" = "$BASE_TREE" ] && [ ! -e "$MV/.archive" ] && [ ! -e "$PRIV" ] \
   && [ -z "$(git -C "$MIG/repo" diff --cached --stat HEAD~2)" ] \
   && [ "$(git -C "$MIG/repo" status --porcelain | grep '^??')" = "$BASE_STATUS" ]; then
  pass "restore returns both archives to the original tree"
else
  fail "restore returns both archives to the original tree" "$(git -C "$MIG/repo" status --short | head -3 | tr '\n' ' ')"
fi

# --- 4c. Interrupted migrations ---
# A stand-in command kills the migration script with SIGKILL, as a crash or a
# power cut would, on the Nth call whose arguments contain a marker. No trap
# runs, so the lock is left behind too.
crash_on() {
  local real
  real=$(command -v "$1")
  CRASH_BIN=$(mktemp -d)
  cat >"$CRASH_BIN/$1" <<SHIM
#!/bin/bash
if [[ " \$* " == *"$2"* ]]; then
  n=\$(( \$(cat "$CRASH_BIN/count" 2>/dev/null || echo 0) + 1 ))
  echo "\$n" >"$CRASH_BIN/count"
  [ "\$n" = "$3" ] && { kill -9 "\$PPID"; exit 137; }
fi
exec "$real" "\$@"
SHIM
  chmod +x "$CRASH_BIN/$1"
}
crashed() { (PATH="$CRASH_BIN:$PATH" HOME="$MIG" bash "$MIGRATE" "$@") >/dev/null 2>&1; }
migrate() { HOME="$MIG" bash "$MIGRATE" "$@" >/dev/null 2>&1; }
LOCK_DIR="$MIG/repo/.git/agent-memory-migrate.lock"
# The vault matches the base commit, with the restore hint for the one
# tracked private file applied.
at_base() {
  git -C "$MIG/repo" add -- vaults/demo/JRNL/AGNT/2026-04-24-1500.md 2>/dev/null
  [ "$(tree_sum)" = "$BASE_TREE" ] && [ ! -e "$MV/.archive" ] && [ ! -e "$PRIV" ] \
    && [ ! -e "$LOCK_DIR" ] && git -C "$MIG/repo" diff --cached --quiet "$BASE_COMMIT" \
    && [ "$(git -C "$MIG/repo" status --porcelain | grep '^??')" = "$BASE_STATUS" ]
}
LOGS=(archive --vault "$MV" --scope logs --private-dir "$PRIV" --allow-inbound-links --apply --yes)
git -C "$MIG/repo" reset -q "$BASE_COMMIT"

crash_on git " mv " 2
crashed archive --vault "$MV" --scope rules --apply
rc=$?
[ "$rc" = 137 ] && [ -d "$LOCK_DIR" ] \
  && [ "$(find "$MV/.archive/agent-memory" -type f ! -name MANIFEST.tsv | wc -l)" = 1 ] \
  && migrate restore --vault "$MV" --apply && at_base \
  && pass "restore undoes an archive killed between git mv calls" \
  || fail "restore undoes an archive killed between git mv calls" "exit $rc"
rm -rf "$CRASH_BIN"

crash_on git " mv " 2
crashed archive --vault "$MV" --scope rules --apply
rc=$?
migrate archive --vault "$MV" --scope rules --apply
if [ "$rc" = 137 ] && [ ! -e "$MV/AGNT" ] && [ ! -e "$MV/_SYS/JDEX_AGNT.base" ] \
   && [ "$(grep -c '^file' "$MV/.archive/agent-memory/MANIFEST.tsv")" = 3 ] \
   && [ "$(git -C "$MIG/repo" diff --cached --name-status | grep -c '^R100')" = 3 ]; then
  pass "re-running archive finishes a Git archive killed midway"
else
  fail "re-running archive finishes a Git archive killed midway"
fi
migrate restore --vault "$MV" --apply && at_base || fail "restore after a resumed Git archive"
rm -rf "$CRASH_BIN"

# Killed after the private copy of a tracked log is recorded and unstaged,
# before the original is deleted, so both copies exist.
crash_on rm "JRNL/AGNT/2026-04-24-1500.md" 1
crashed "${LOGS[@]}"
rc=$?
[ "$rc" = 137 ] && [ -f "$MV/JRNL/AGNT/2026-04-24-1500.md" ] && [ -f "$PRIV/JRNL/AGNT/2026-04-24-1500.md" ] \
  && migrate restore --vault "$MV" --private-dir "$PRIV" --apply && at_base \
  && pass "restore undoes an archive killed before a private original was removed" \
  || fail "restore undoes an archive killed before a private original was removed" "exit $rc"
rm -rf "$CRASH_BIN"

crash_on rm "JRNL/AGNT/2026-04-24-1500.md" 1
crashed "${LOGS[@]}"
rc=$?
migrate "${LOGS[@]}"
if [ "$rc" = 137 ] && [ ! -e "$MV/JRNL/AGNT" ] && [ -f "$PRIV/JRNL/AGNT/2026-04-24-1500.md" ] \
   && [ -f "$PRIV/JRNL/AGNT/2026-04-25-0900.md" ] \
   && [ "$(grep -c '^file' "$PRIV/PRIVATE-MANIFEST.tsv")" = 2 ] \
   && (cd "$PRIV" && awk -F'\t' '$1 == "file" { print $2 "  " $5 }' PRIVATE-MANIFEST.tsv | sha256sum -c --quiet) \
   && ! git -C "$MIG/repo" ls-files --error-unmatch vaults/demo/JRNL/AGNT/2026-04-24-1500.md >/dev/null 2>&1; then
  pass "re-running archive finishes a private archive killed midway"
else
  fail "re-running archive finishes a private archive killed midway"
fi
migrate restore --vault "$MV" --private-dir "$PRIV" --apply && at_base || fail "restore after a resumed private archive"
rm -rf "$CRASH_BIN"

# Killed while the second private copy still has its temporary name.
crash_on mv ".agent-memory-partial" 2
crashed "${LOGS[@]}"
rc=$?
[ "$rc" = 137 ] && [ -n "$(find "$PRIV" -name '*.agent-memory-partial')" ] \
  && [ ! -e "$PRIV/JRNL/AGNT/2026-04-25-0900.md" ] \
  && migrate restore --vault "$MV" --private-dir "$PRIV" --apply && at_base \
  && pass "restore undoes an archive killed mid-copy and removes the partial copy" \
  || fail "restore undoes an archive killed mid-copy and removes the partial copy" "exit $rc"
rm -rf "$CRASH_BIN"

# One altered archive file stops the restore before anything moves.
migrate "${LOGS[@]}"
ARCHIVED="$MV/.archive/agent-memory/JRNL/AGNT/2026-04-23-1000.md"
cp "$ARCHIVED" "$MIG/saved.md"
echo "edited" >>"$ARCHIVED"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply
rc=$?
[ "$rc" = 2 ] && [ ! -e "$MV/JRNL/AGNT" ] && [ -f "$PRIV/JRNL/AGNT/2026-04-24-1500.md" ] \
  && [ -f "$PRIV/PRIVATE-MANIFEST.tsv" ] && [ -f "$MV/.archive/agent-memory/MANIFEST.tsv" ] \
  && pass "restore checks every checksum before it moves anything" \
  || fail "restore checks every checksum before it moves anything" "exit $rc"
cp "$MIG/saved.md" "$ARCHIVED"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply && at_base || fail "restore after a checksum refusal"

# A manifest path outside the legacy folders stops restore before it reads,
# copies, or deletes anything. "../victim.md" from the private archive is a
# file beside it, and following the path would move that file into vaults/.
migrate "${LOGS[@]}"
printf 'outside the archive\n' >"$MIG/private/victim.md"
cp "$PRIV/PRIVATE-MANIFEST.tsv" "$MIG/saved.tsv"
printf 'file\t%s\ttracked\trequested\t../victim.md\n' \
  "$(sha256sum "$MIG/private/victim.md" | cut -d' ' -f1)" >>"$PRIV/PRIVATE-MANIFEST.tsv"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply
rc_private=$?
cp "$MIG/saved.tsv" "$PRIV/PRIVATE-MANIFEST.tsv"
GM="$MV/.archive/agent-memory/MANIFEST.tsv"
cp "$GM" "$MIG/saved.tsv"
awk -F'\t' -v OFS='\t' '$NF == "JRNL/AGNT/2026-04-23-1000.md" { $NF = "LIFE/2026-04-23-1000.md" } 1' \
  "$MIG/saved.tsv" >"$GM"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply
rc_git=$?
cp "$MIG/saved.tsv" "$GM"
[ "$rc_private" = 2 ] && [ "$rc_git" = 2 ] && [ -f "$MIG/private/victim.md" ] \
  && [ ! -e "$MIG/repo/vaults/victim.md" ] && [ ! -e "$MV/JRNL/AGNT" ] && [ ! -e "$MV/LIFE/2026-04-23-1000.md" ] \
  && pass "restore refuses manifest paths outside the legacy folders" \
  || fail "restore refuses manifest paths outside the legacy folders" "private $rc_private, git $rc_git"
rm -f "$MIG/private/victim.md"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply && at_base || fail "restore after a path refusal"

# A symlinked folder on either side of a move stops the run before anything
# goes through it: JRNL/AGNT in the vault, a folder in the private archive,
# or .archive before archive creates it.
OUTSIDE="$MIG/outside"
mkdir -p "$OUTSIDE"
migrate "${LOGS[@]}"
ln -s "$OUTSIDE" "$MV/JRNL/AGNT"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply
rc_vault=$?
rm "$MV/JRNL/AGNT"
mv "$PRIV/JRNL/AGNT" "$OUTSIDE/AGNT" && ln -s "$OUTSIDE/AGNT" "$PRIV/JRNL/AGNT"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply
rc_private=$?
rm "$PRIV/JRNL/AGNT" && mv "$OUTSIDE/AGNT" "$PRIV/JRNL/AGNT"
outside_empty=$(find "$OUTSIDE" -mindepth 1 | wc -l)
migrate restore --vault "$MV" --private-dir "$PRIV" --apply && at_base || fail "restore after a symlink refusal"
ln -s "$OUTSIDE" "$MV/.archive"
migrate archive --vault "$MV" --scope rules --apply
rc_archive=$?
rm "$MV/.archive"
[ "$rc_vault" = 2 ] && [ "$rc_private" = 2 ] && [ "$rc_archive" = 2 ] && [ "$outside_empty" = 0 ] \
  && [ -z "$(find "$OUTSIDE" -mindepth 1)" ] && at_base \
  && pass "archive and restore refuse to move files through a symlinked folder" \
  || fail "archive and restore refuse to move files through a symlinked folder" \
       "vault $rc_vault, private $rc_private, archive $rc_archive, outside $outside_empty"

# A live process holding the lock blocks both commands.
sleep 30 &
LIVE=$!
mkdir "$LOCK_DIR" && echo "$LIVE" >"$LOCK_DIR/pid"
migrate "${LOGS[@]}"
rc_archive=$?
migrate restore --vault "$MV" --private-dir "$PRIV" --apply
rc_restore=$?
[ "$rc_archive" = 2 ] && [ "$rc_restore" = 2 ] && [ "$(tree_sum)" = "$BASE_TREE" ] && [ ! -e "$PRIV" ] \
  && pass "a running migration blocks a second archive or restore" \
  || fail "a running migration blocks a second archive or restore" "archive $rc_archive, restore $rc_restore"
kill "$LIVE" 2>/dev/null
wait "$LIVE" 2>/dev/null
rm -rf "$LOCK_DIR"

# A second vault with the same folder name, pointed at the first vault's
# private archive, is refused before it reads or writes anything there.
migrate "${LOGS[@]}"
OTHER="$MIG/other/demo"
mkdir -p "$OTHER/JRNL/AGNT"
printf '# Session log\n\nAnother vault.\n' >"$OTHER/JRNL/AGNT/2026-05-01-0800.md"
PSUM=$(cd "$PRIV" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum)
migrate archive --vault "$OTHER" --private-dir "$PRIV" --apply --yes
rc_archive=$?
migrate restore --vault "$OTHER" --private-dir "$PRIV" --apply
rc_restore=$?
[ "$rc_archive" = 2 ] && [ "$rc_restore" = 2 ] && [ -f "$OTHER/JRNL/AGNT/2026-05-01-0800.md" ] \
  && [ ! -e "$OTHER/JRNL/AGNT/2026-04-24-1500.md" ] \
  && [ "$(cd "$PRIV" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum)" = "$PSUM" ] \
  && pass "a private archive refuses a vault that did not write it" \
  || fail "a private archive refuses a vault that did not write it" "archive $rc_archive, restore $rc_restore"
migrate restore --vault "$MV" --private-dir "$PRIV" --apply && at_base || fail "restore after an owner refusal"

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

# expect_incomplete NAME HOME MCP_CMD [ARGS] runs the migration with no input
# and expects it to refuse to report success. It leaves the output in $out.
expect_incomplete() {
  local name=$1 home=$2 mcp_cmd=$3
  shift 3
  if out=$(HOME="$home" MCP_CMD="$mcp_cmd" ./scripts/migrate-v2.sh "$@" </dev/null 2>&1); then
    fail "$name" "exited 0"
  elif echo "$out" | grep -q "Migration incomplete"; then
    pass "$name"
  else
    fail "$name" "$(echo "$out" | tail -3 | tr '\n' ' ')"
  fi
}

MIGRATE_HOME=$(mktemp -d)
expect_incomplete "migrate-v2.sh reports a missing config as incomplete" "$MIGRATE_HOME" true --yes
jq -n --arg vault "$WORK_DIR/vaults/example" --arg workspace "$WORK_DIR" \
  '{vault_path: $vault, workspace_path: $workspace}' >"$MIGRATE_HOME/.obsidian-mcp.config.json"
expect_incomplete "migrate-v2.sh reports a declined rebuild as incomplete" "$MIGRATE_HOME" true

expect_incomplete "migrate-v2.sh reports a failed rebuild as incomplete" "$MIGRATE_HOME" false --yes
if echo "$out" | grep -q "The rebuild failed" \
  && echo "$out" | grep -q -- "--- 8. Regenerating harness assets ---"; then
  pass "migrate-v2.sh finishes the migration after a failed rebuild"
else
  fail "migrate-v2.sh finishes the migration after a failed rebuild" \
    "$(echo "$out" | tail -3 | tr '\n' ' ')"
fi

# Without jq, config detection would fail as though no config existed. A
# custom MCP_CMD needs neither node nor npx.
STUB_BIN=$(mktemp -d)
ln -sf "$(command -v git)" "$STUB_BIN/git"
if out=$(env -i PATH="$STUB_BIN" HOME="$MIGRATE_HOME" ./scripts/migrate-v2.sh --yes 2>&1); then
  fail "migrate-v2.sh requires jq" "exited 0"
elif echo "$out" | grep -q "'jq' is required"; then
  pass "migrate-v2.sh requires jq"
else
  fail "migrate-v2.sh requires jq" "$(echo "$out" | tail -3 | tr '\n' ' ')"
fi
ln -sf "$(command -v jq)" "$STUB_BIN/jq"
out=$(env -i PATH="$STUB_BIN" HOME="$MIGRATE_HOME" MCP_CMD=false ./scripts/migrate-v2.sh --yes 2>&1)
if echo "$out" | grep -q "is required but not installed"; then
  fail "migrate-v2.sh needs only jq with a custom MCP_CMD" "$(echo "$out" | grep 'is required')"
else
  pass "migrate-v2.sh needs only jq with a custom MCP_CMD"
fi
rm -rf "$MIGRATE_HOME" "$STUB_BIN"

printf 'legacy\n' >.gitattributes
echo '.gemini-obsidian/**/*.lance filter=lfs diff=lfs merge=lfs -text' >>.gitattributes
check "migrate-v2.sh runs directly and non-interactively" ./scripts/migrate-v2.sh --yes

if grep -q '.obsidian-vault-mcp/' .gitattributes && ! grep -q '.gemini-obsidian/' .gitattributes; then
  pass "migrate-v2.sh rewrites LFS globs"
else
  fail "migrate-v2.sh rewrites LFS globs" "$(cat .gitattributes | tr '\n' ' ')"
fi

check "migrate-v2.sh is re-runnable" ./scripts/migrate-v2.sh --yes

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
  MCP_EXECUTABLE=$(npx --yes --package=@jabez007/obsidian-vault-mcp@2.3.0 -c 'command -v obsidian-vault-mcp')
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
