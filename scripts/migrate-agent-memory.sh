#!/bin/bash

# migrate-agent-memory.sh
# Reviews and retires the legacy vault-based agent memory: AGNT/ procedural
# rules, JRNL/AGNT/ session logs, and the hooks that used to write them.
#
# Every command is read-only unless --apply is given. Nothing here edits note
# content, deletes a note, or contacts a memory provider. Archiving uses
# `git mv`, so history is preserved and `restore` reverses it.
#
# Usage:
#   ./scripts/migrate-agent-memory.sh inventory    [--vault DIR] [--format text|tsv]
#   ./scripts/migrate-agent-memory.sh archive      [--vault DIR] [--scope all|logs|rules]
#                                                  [--apply] [--allow-inbound-links]
#   ./scripts/migrate-agent-memory.sh restore      [--vault DIR] [--apply]
#   ./scripts/migrate-agent-memory.sh legacy-hooks [--apply]
#
# --vault defaults to vault_path in ~/.obsidian-mcp.config.json.
# --scope logs archives JRNL/AGNT/ only; rules archives AGNT/ and its Base.
# Scopes can be archived separately; restore reverses everything archived.
#
# Exit codes: 0 success, 1 usage or environment error, 2 refused because a
# precondition failed (untracked files, inbound links, existing archive).

set -euo pipefail

ARCHIVE_REL=".archive/agent-memory"
MANIFEST_NAME="MANIFEST.tsv"
# Roots of the legacy convention, relative to the vault. Order matters for
# restore only in that each is moved as one unit.
LEGACY_ROOTS=("AGNT" "JRNL/AGNT" "_SYS/JDEX_AGNT.base")
GEMINI_HOOK_NAME="agent-memory-boot"
# Credential-shaped text. Matches are a prompt for human review, not proof.
SENSITIVE_REGEX='(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|password|passwd|private key|bearer [a-z0-9._-]{12,}|ghp_[a-z0-9]{20,}|github_pat_|sk-[a-z0-9_-]{20,}|akia[0-9a-z]{16}|xox[abpr]-)'

COMMAND=${1:-}
[ $# -gt 0 ] && shift

VAULT_ARG=""
APPLY=0
ALLOW_INBOUND=0
FORMAT="text"
SCOPE="all"

usage() {
  sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT_ARG=${2:-}; shift 2 ;;
    --vault=*) VAULT_ARG=${1#--vault=}; shift ;;
    --apply) APPLY=1; shift ;;
    --allow-inbound-links) ALLOW_INBOUND=1; shift ;;
    --format) FORMAT=${2:-}; shift 2 ;;
    --format=*) FORMAT=${1#--format=}; shift ;;
    --scope) SCOPE=${2:-}; shift 2 ;;
    --scope=*) SCOPE=${1#--scope=}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown option '$1'." >&2; usage >&2; exit 1 ;;
  esac
done

case "$FORMAT" in text|tsv) ;; *) echo "Error: --format must be text or tsv." >&2; exit 1 ;; esac
case "$SCOPE" in all|logs|rules) ;; *) echo "Error: --scope must be all, logs, or rules." >&2; exit 1 ;; esac

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

resolve_vault() {
  local candidate=$VAULT_ARG
  if [ -z "$candidate" ]; then
    local cfg
    for cfg in "$HOME/.obsidian-mcp.config.json" "$HOME/.gemini-obsidian.config.json"; do
      if [ -f "$cfg" ]; then
        candidate=$(jq -r '.vault_path // empty' "$cfg" 2>/dev/null || true)
        [ -n "$candidate" ] && break
      fi
    done
  fi
  if [ -z "$candidate" ]; then
    echo "Error: no vault given and none configured. Pass --vault DIR." >&2
    exit 1
  fi
  if [ ! -d "$candidate" ]; then
    echo "Error: vault directory '$candidate' does not exist." >&2
    exit 1
  fi
  VAULT=$(cd "$candidate" && pwd -P)
  GIT_ROOT=$(git -C "$VAULT" rev-parse --show-toplevel 2>/dev/null || true)
}

# Every file under the given legacy roots (default: all), vault-relative.
legacy_files() {
  local root roots=("$@")
  [ ${#roots[@]} -gt 0 ] || roots=("${LEGACY_ROOTS[@]}")
  for root in "${roots[@]}"; do
    if [ -f "$VAULT/$root" ]; then
      echo "$root"
    elif [ -d "$VAULT/$root" ]; then
      (cd "$VAULT" && find "$root" -type f | LC_ALL=C sort)
    fi
  done
}

# Legacy roots that exist and fall inside --scope.
present_roots() {
  local root
  for root in "${LEGACY_ROOTS[@]}"; do
    case "$SCOPE:$root" in
      all:*|logs:JRNL/AGNT|rules:AGNT|rules:_SYS/JDEX_AGNT.base) ;;
      *) continue ;;
    esac
    [ -e "$VAULT/$root" ] && echo "$root"
  done
  return 0
}

# Markdown notes outside the legacy roots and outside hidden paths: the notes
# a person curates and the MCP indexes.
curated_notes() {
  # -mindepth 1 keeps the prune from matching "." itself.
  (cd "$VAULT" && find . -mindepth 1 -name '.*' -prune -o -type f -name '*.md' -print \
    | sed 's|^\./||' \
    | grep -v -e '^AGNT/' -e '^JRNL/AGNT/' \
    | LC_ALL=C sort) || true
}

kind_of() {
  case "$1" in
    AGNT/00-IDX/*) echo "system-index" ;;
    AGNT/*) echo "procedural-rule" ;;
    JRNL/AGNT/*) echo "session-log" ;;
    *.base) echo "base-config" ;;
    *) echo "other" ;;
  esac
}

# tracked | untracked | modified | no-git
git_state() {
  if [ -z "$GIT_ROOT" ]; then echo "no-git"; return; fi
  local status
  status=$(git -C "$VAULT" status --porcelain=v1 --untracked-files=all -- "$1" 2>/dev/null | head -n 1)
  case "$status" in
    "") echo "tracked" ;;
    "??"*) echo "untracked" ;;
    *) echo "modified" ;;
  esac
}

# Short description: a session log's goal, otherwise the first heading.
describe() {
  local f="$VAULT/$1"
  case "$1" in *.md) ;; *) echo "-"; return ;; esac
  awk '
    /\*\*Goal:\*\*/ { line = $0; sub(/.*\*\*Goal:\*\*[[:space:]]*/, "", line); if (line != "") { print line; exit } }
    /^#+[[:space:]]*Goal[[:space:]]*:?[[:space:]]*$/ { want = 1; next }
    want && NF { print; exit }
    !h && /^# / { h = substr($0, 3) }
    END { if (h != "") print h }
  ' "$f" 2>/dev/null | head -n 1 | tr -d '\r' | tr '\t' ' ' | cut -c1-100
}

is_sensitive() {
  grep -Eiq "$SENSITIVE_REGEX" "$VAULT/$1" 2>/dev/null
}

# Curated notes that link to or embed the given legacy file.
inbound_links() {
  local rel=$1 base noext relnoext
  base=$(basename "$rel")
  noext=${base%.md}
  relnoext=${rel%.md}
  local patterns=() name suffix
  for name in "$base" "$noext" "$rel" "$relnoext"; do
    for suffix in "]]" "|" "#" "^"; do
      patterns+=(-e "[[$name$suffix")
    done
  done
  [ -n "$CURATED" ] || return 0
  (cd "$VAULT" && printf '%s\n' "$CURATED" | tr '\n' '\0' \
    | xargs -0 grep -lF "${patterns[@]}" 2>/dev/null) || true
}

# Legacy hook leftovers: the global Gemini hook and repo-local hook files.
report_hooks() {
  local settings="$HOME/.gemini/settings.json"
  if [ -f "$settings" ] && jq -e --arg n "$GEMINI_HOOK_NAME" \
       '[.hooks.SessionStart[]?.hooks[]? | select(.name == $n)] | length > 0' "$settings" >/dev/null 2>&1; then
    echo "  Gemini global hook '$GEMINI_HOOK_NAME' is registered in $settings."
    echo "    Remove it with: $0 legacy-hooks --apply"
  else
    echo "  Gemini global hook: not registered."
  fi
  local root
  for root in ${GIT_ROOT:+"$GIT_ROOT"}; do
    local f
    for f in scripts/agent-memory-context.sh .claude/hooks/session-start.sh .codex/hooks/session-start.sh; do
      if [ -f "$root/$f" ]; then
        echo "  $root/$f still exists. Merge the template update that retires it."
      fi
    done
  done
}

cmd_inventory() {
  resolve_vault
  CURATED=$(curated_notes)
  local files
  files=$(legacy_files)

  if [ "$FORMAT" = "tsv" ]; then
    printf 'path\tkind\tgit_state\tinbound_links\tsensitive\tdescription\n'
    [ -z "$files" ] && return 0
    while IFS= read -r rel; do
      local links sens
      links=$(inbound_links "$rel" | wc -l | tr -d ' ')
      if is_sensitive "$rel"; then sens=yes; else sens=no; fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$(kind_of "$rel")" "$(git_state "$rel")" \
        "$links" "$sens" "$(describe "$rel")"
    done <<<"$files"
    return 0
  fi

  echo "Agent-memory inventory (read-only)"
  echo "Vault: $VAULT"
  echo "Git:   ${GIT_ROOT:-not a Git repository}"
  echo ""

  if [ -f "$VAULT/$ARCHIVE_REL/$MANIFEST_NAME" ]; then
    echo "An archive already exists at $ARCHIVE_REL/. Use 'restore' to reverse it."
    echo ""
  fi

  if [ -z "$files" ]; then
    echo "No legacy agent-memory content found."
    echo ""
    echo "Legacy hooks:"
    report_hooks
    return 0
  fi

  local rules=0 logs=0 other=0 untracked=0 sensitive=0 referenced=0
  local section_rules="" section_logs="" section_other="" section_links="" section_sens=""
  while IFS= read -r rel; do
    local kind state desc links
    kind=$(kind_of "$rel")
    state=$(git_state "$rel")
    desc=$(describe "$rel")
    links=$(inbound_links "$rel")
    [ "$state" != "tracked" ] && untracked=$((untracked + 1))
    local line="  [$state] $rel"
    [ "$desc" != "-" ] && [ -n "$desc" ] && line="$line :: $desc"
    case "$kind" in
      procedural-rule) rules=$((rules + 1)); section_rules+="$line"$'\n' ;;
      session-log) logs=$((logs + 1)); section_logs+="$line"$'\n' ;;
      *) other=$((other + 1)); section_other+="$line"$'\n' ;;
    esac
    if [ -n "$links" ]; then
      referenced=$((referenced + 1))
      section_links+="  $rel <- $(echo "$links" | paste -sd ',' - | sed 's/,/, /g')"$'\n'
    fi
    if is_sensitive "$rel"; then
      sensitive=$((sensitive + 1))
      section_sens+="  $rel"$'\n'
    fi
  done <<<"$files"

  echo "Procedural rules (AGNT/): $rules"
  echo "  Agent operating state. Review each one: a rule about how you work or a"
  echo "  decision you made may deserve a curated note; a rule about how an agent"
  echo "  should behave belongs in agent instructions or a memory provider."
  printf '%s' "$section_rules"
  echo ""
  echo "Session logs (JRNL/AGNT/): $logs"
  echo "  Session telemetry. Promote only a durable insight, never the log itself."
  printf '%s' "$section_logs"
  if [ "$other" -gt 0 ]; then
    echo ""
    echo "Indexes and configuration: $other"
    printf '%s' "$section_other"
  fi
  echo ""
  echo "Referenced from curated notes: $referenced"
  if [ "$referenced" -gt 0 ]; then
    echo "  Archiving breaks these links. Edit the linking notes first, or accept the"
    echo "  broken links with archive --allow-inbound-links."
    printf '%s' "$section_links"
  fi
  echo ""
  echo "Possible credentials or private data: $sensitive"
  if [ "$sensitive" -gt 0 ]; then
    echo "  Do not promote these without redaction."
    printf '%s' "$section_sens"
  fi
  echo ""
  echo "Not tracked or modified in Git: $untracked"
  if [ "$untracked" -gt 0 ]; then
    echo "  Commit these before archiving so their history is kept."
  fi
  echo ""
  echo "Legacy hooks:"
  report_hooks
  echo ""
  echo "Next steps:"
  echo "  1. Promote any knowledge worth keeping with the librarian's promotion"
  echo "     workflow (references/librarian/knowledge-promotion.md)."
  echo "  2. Preview the archive:  $0 archive --vault \"$VAULT\""
  echo "  3. Apply it:             $0 archive --vault \"$VAULT\" --apply"
}

require_git() {
  if [ -z "$GIT_ROOT" ]; then
    echo "Refused: $VAULT is not inside a Git repository, so a move could not be" >&2
    echo "reversed from history. Commit the vault to Git first." >&2
    exit 2
  fi
}

cmd_archive() {
  resolve_vault
  require_git
  local dest="$VAULT/$ARCHIVE_REL"

  local roots files root_list=()
  roots=$(present_roots)
  if [ -z "$roots" ]; then
    echo "No legacy agent-memory content in scope '$SCOPE'. Nothing to archive."
    return 0
  fi
  while IFS= read -r rel; do root_list+=("$rel"); done <<<"$roots"
  files=$(legacy_files "${root_list[@]}")

  local blocked=0 rel
  # Untracked or modified files would lose history or uncommitted edits.
  local dirty
  dirty=$(cd "$VAULT" && git status --porcelain=v1 --untracked-files=all -- "${root_list[@]}" 2>/dev/null || true)
  if [ -n "$dirty" ]; then
    echo "Refused: these legacy files are untracked or have uncommitted changes:" >&2
    echo "$dirty" | sed 's/^/  /' >&2
    echo "Commit them first so the archive keeps their history." >&2
    blocked=1
  fi

  CURATED=$(curated_notes)
  local linked=""
  while IFS= read -r rel; do
    local l
    l=$(inbound_links "$rel")
    [ -n "$l" ] && linked+="  $rel <- $(echo "$l" | paste -sd ',' - | sed 's/,/, /g')"$'\n'
  done <<<"$files"
  if [ -n "$linked" ] && [ "$ALLOW_INBOUND" != "1" ]; then
    echo "Refused: curated notes link to legacy content, and archiving would break" >&2
    echo "those links:" >&2
    printf '%s' "$linked" >&2
    echo "Edit those notes first, or pass --allow-inbound-links to accept the broken links." >&2
    blocked=1
  fi

  for rel in "${root_list[@]}"; do
    if [ -e "$dest/$rel" ]; then
      echo "Refused: $dest/$rel already exists." >&2
      blocked=1
    fi
  done

  echo "Archive plan for $VAULT (scope: $SCOPE)"
  echo "  Destination: $ARCHIVE_REL/ (hidden, so Obsidian and the MCP index skip it)"
  while IFS= read -r rel; do
    echo "  move $rel -> $ARCHIVE_REL/$rel"
  done <<<"$roots"
  echo "  $(echo "$files" | wc -l | tr -d ' ') files; note content is not modified."
  [ -n "$linked" ] && echo "  Inbound links that will break: $(printf '%s' "$linked" | wc -l | tr -d ' ')"

  if [ "$blocked" = "1" ]; then
    exit 2
  fi
  if [ "$APPLY" != "1" ]; then
    echo ""
    echo "Dry run. Re-run with --apply to perform the move."
    return 0
  fi

  mkdir -p "$dest"
  local manifest="$dest/$MANIFEST_NAME"
  # Append, so separately archived scopes share one manifest and one restore.
  if [ ! -f "$manifest" ]; then
    printf '# Legacy agent memory archived by scripts/migrate-agent-memory.sh\n' >"$manifest"
    printf '# kind\tsha256-or-dash\tpath\n' >>"$manifest"
  fi
  {
    while IFS= read -r rel; do
      printf 'root\t-\t%s\n' "$rel"
    done <<<"$roots"
    while IFS= read -r rel; do
      printf 'file\t%s\t%s\n' "$(sha256 "$VAULT/$rel")" "$rel"
    done <<<"$files"
  } >>"$manifest"

  while IFS= read -r rel; do
    mkdir -p "$(dirname "$dest/$rel")"
    git -C "$VAULT" mv -- "$rel" "$ARCHIVE_REL/$rel"
  done <<<"$roots"
  git -C "$VAULT" add -- "$ARCHIVE_REL/$MANIFEST_NAME"

  # Verify every file arrived unchanged before reporting success.
  local bad=0 kind hash path
  while IFS=$'\t' read -r kind hash path; do
    [ "$kind" = "file" ] || continue
    if [ "$(sha256 "$dest/$path")" != "$hash" ]; then
      echo "Error: $path changed during the move." >&2
      bad=1
    fi
  done <"$manifest"
  [ "$bad" = "0" ] || exit 1

  echo ""
  echo "Archived and staged. Review with 'git -C \"$VAULT\" status', then commit, e.g.:"
  echo "  git -C \"$VAULT\" commit -m \"Archive legacy agent memory\""
  echo "Undo before committing with: $0 restore --vault \"$VAULT\" --apply"
  echo "The next commit's index hook drops the archived notes from search."
}

cmd_restore() {
  resolve_vault
  require_git
  local dest="$VAULT/$ARCHIVE_REL"
  local manifest="$dest/$MANIFEST_NAME"
  if [ ! -f "$manifest" ]; then
    echo "No archive manifest at $manifest. Nothing to restore."
    return 0
  fi

  local roots kind hash path blocked=0
  roots=$(awk -F'\t' '$1 == "root" { print $3 }' "$manifest")
  echo "Restore plan for $VAULT"
  while IFS= read -r path; do
    echo "  move $ARCHIVE_REL/$path -> $path"
    if [ -e "$VAULT/$path" ]; then
      echo "Refused: $VAULT/$path already exists." >&2
      blocked=1
    fi
    if [ ! -e "$dest/$path" ]; then
      echo "Refused: $dest/$path is missing from the archive." >&2
      blocked=1
    fi
  done <<<"$roots"
  [ "$blocked" = "0" ] || exit 2

  if [ "$APPLY" != "1" ]; then
    echo ""
    echo "Dry run. Re-run with --apply to perform the move."
    return 0
  fi

  while IFS= read -r path; do
    mkdir -p "$(dirname "$VAULT/$path")"
    git -C "$VAULT" mv -- "$ARCHIVE_REL/$path" "$path"
  done <<<"$roots"

  local bad=0
  while IFS=$'\t' read -r kind hash path; do
    [ "$kind" = "file" ] || continue
    if [ "$(sha256 "$VAULT/$path")" != "$hash" ]; then
      echo "Error: $path does not match its archived checksum." >&2
      bad=1
    fi
  done <"$manifest"
  [ "$bad" = "0" ] || exit 1

  git -C "$VAULT" rm -q --cached -- "$ARCHIVE_REL/$MANIFEST_NAME" 2>/dev/null || true
  rm -f "$manifest"
  # Remove now-empty archive directories, never anything with content.
  find "$VAULT/.archive" -depth -type d -empty -delete 2>/dev/null || true

  echo ""
  echo "Restored and staged. Review with 'git -C \"$VAULT\" status', then commit."
}

cmd_legacy_hooks() {
  local settings="$HOME/.gemini/settings.json"
  local hooks_dir="$HOME/.gemini/hooks"
  local registered=0
  if [ -f "$settings" ] && jq -e --arg n "$GEMINI_HOOK_NAME" \
       '[.hooks.SessionStart[]?.hooks[]? | select(.name == $n)] | length > 0' "$settings" >/dev/null 2>&1; then
    registered=1
  fi

  # Only delete files that carry the marker the old setup wrote into them.
  local stale=()
  [ -f "$hooks_dir/agent-memory-boot.sh" ] && \
    grep -q 'Generated by johnny-decimal-zettelkasten' "$hooks_dir/agent-memory-boot.sh" && \
    stale+=("$hooks_dir/agent-memory-boot.sh")
  [ -f "$hooks_dir/agent-memory-context.sh" ] && \
    grep -q 'Canonical Agent Memory boot context' "$hooks_dir/agent-memory-context.sh" && \
    stale+=("$hooks_dir/agent-memory-context.sh")

  if [ "$registered" = "0" ] && [ ${#stale[@]} -eq 0 ]; then
    echo "No legacy Gemini agent-memory hook found."
    return 0
  fi

  [ "$registered" = "1" ] && echo "Registered in $settings: SessionStart hook '$GEMINI_HOOK_NAME'"
  local f
  for f in "${stale[@]}"; do echo "Generated file: $f"; done

  if [ "$APPLY" != "1" ]; then
    echo "Dry run. Re-run with --apply to remove them."
    return 0
  fi

  if [ "$registered" = "1" ]; then
    cp "$settings" "$settings.agent-memory-backup"
    local tmp
    tmp=$(mktemp)
    # Drop only our named hook, then any matcher group or event list it left
    # empty. Entries without a hooks array are left alone.
    jq --arg n "$GEMINI_HOOK_NAME" '
      .hooks.SessionStart |= (
        map(if (.hooks | type) == "array" then .hooks |= map(select(.name != $n)) else . end)
        | map(select((.hooks | type) != "array" or (.hooks | length) > 0)))
      | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$settings" >"$tmp" && mv "$tmp" "$settings"
    echo "Removed the registration. Backup: $settings.agent-memory-backup"
  fi
  for f in "${stale[@]}"; do
    rm -f "$f"
    echo "Removed $f"
  done
}

case "$COMMAND" in
  inventory) cmd_inventory ;;
  archive) cmd_archive ;;
  restore) cmd_restore ;;
  legacy-hooks) cmd_legacy_hooks ;;
  ""|-h|--help|help) usage ;;
  *) echo "Error: unknown command '$COMMAND'." >&2; usage >&2; exit 1 ;;
esac
