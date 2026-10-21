#!/bin/bash

# migrate-agent-memory.sh
# Reviews and retires the legacy vault-based agent memory: AGNT/ procedural
# rules, JRNL/AGNT/ session logs, and the hooks that used to write them.
#
# Every command is read-only unless --apply is given. Nothing here edits note
# content, commits, or contacts a memory provider.
#
# archive sorts each legacy file into one of two places:
#   - Git archive: committed, unmodified files with no credential-shaped text.
#     `git mv` moves them to <vault>/.archive/agent-memory/ and Git keeps them.
#   - Private archive: untracked, modified, or credential-shaped files, files
#     named with --private, and every file in a vault outside Git. They move to
#     --private-dir, which must sit outside any Git repository, and never enter
#     Git. Moving them needs --apply and a typed "yes", or --yes.
# Both archives record SHA-256 checksums and `restore` reverses both.
#
# Usage:
#   ./scripts/migrate-agent-memory.sh inventory    [--vault DIR] [--format text|tsv]
#                                                  [--private PATH]...
#   ./scripts/migrate-agent-memory.sh archive      [--vault DIR] [--scope all|logs|rules]
#                                                  [--private-dir DIR] [--private PATH]...
#                                                  [--apply] [--yes] [--allow-inbound-links]
#   ./scripts/migrate-agent-memory.sh restore      [--vault DIR] [--private-dir DIR] [--apply]
#   ./scripts/migrate-agent-memory.sh legacy-hooks [--apply]
#
# --vault defaults to vault_path in ~/.obsidian-mcp.config.json.
# --scope logs archives JRNL/AGNT/ only; rules archives AGNT/ and its Base.
# --private PATH sends a vault-relative legacy file or folder to the private
#   archive even when Git could keep it. Repeat it for more paths.
# Scopes can be archived separately; restore reverses everything archived.
#
# Exit codes: 0 success, 1 usage or environment error, 2 refused because a
# precondition failed (inbound links, missing or unsafe --private-dir, no
# confirmation, existing archive).

set -euo pipefail
# Legacy paths are file names, never globs.
export GIT_LITERAL_PATHSPECS=1

ARCHIVE_REL=".archive/agent-memory"
MANIFEST_NAME="MANIFEST.tsv"
PRIVATE_MANIFEST_NAME="PRIVATE-MANIFEST.tsv"
# Roots of the legacy convention, relative to the vault.
LEGACY_ROOTS=("AGNT" "JRNL/AGNT" "_SYS/JDEX_AGNT.base")
GEMINI_HOOK_NAME="agent-memory-boot"
# Credential-shaped text. Matches are a prompt for human review, not proof.
SENSITIVE_REGEX='(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|password|passwd|private key|bearer [a-z0-9._-]{12,}|ghp_[a-z0-9]{20,}|github_pat_|sk-[a-z0-9_-]{20,}|akia[0-9a-z]{16}|xox[abpr]-)'

COMMAND=${1:-}
[ $# -gt 0 ] && shift

VAULT_ARG=""
APPLY=0
ALLOW_INBOUND=0
ASSUME_YES=0
FORMAT="text"
SCOPE="all"
PRIVATE_DIR_ARG=""
PRIVATE_PATHS=()

usage() {
  awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT_ARG=${2:-}; shift 2 ;;
    --vault=*) VAULT_ARG=${1#--vault=}; shift ;;
    --apply) APPLY=1; shift ;;
    --allow-inbound-links) ALLOW_INBOUND=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --private-dir) PRIVATE_DIR_ARG=${2:-}; shift 2 ;;
    --private-dir=*) PRIVATE_DIR_ARG=${1#--private-dir=}; shift ;;
    --private) PRIVATE_PATHS+=("${2:-}"); shift 2 ;;
    --private=*) PRIVATE_PATHS+=("${1#--private=}"); shift ;;
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

# The private archive must be somewhere Git cannot pick it up: outside the
# vault and outside every Git work tree. The directory may not exist yet, so
# the nearest existing ancestor decides.
resolve_private_dir() {
  PRIVATE_DIR=""
  [ -n "$PRIVATE_DIR_ARG" ] || return 0
  local dir=$PRIVATE_DIR_ARG
  # --private-dir=~/x reaches the script with the tilde unexpanded.
  case "$dir" in \~) dir=$HOME ;; \~/*) dir="$HOME/${dir#\~/}" ;; esac
  case "$dir" in /*) ;; *) dir="$PWD/$dir" ;; esac
  dir=${dir%/}
  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    echo "Error: --private-dir '$dir' is a file, not a directory." >&2
    exit 1
  fi
  local probe=$dir
  while [ ! -d "$probe" ]; do probe=$(dirname "$probe"); done
  probe=$(cd "$probe" && pwd -P)
  case "$probe/" in
    "$VAULT/"*)
      echo "Refused: --private-dir '$dir' is inside the vault." >&2
      exit 2 ;;
  esac
  if git -C "$probe" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Refused: --private-dir '$dir' is inside the Git repository at" >&2
    echo "$(git -C "$probe" rev-parse --show-toplevel). Choose a folder outside every Git repository." >&2
    exit 2
  fi
  PRIVATE_DIR=$dir
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

# Normalize --private paths and reject any that name no legacy file.
check_private_paths() {
  local i p all
  all=$(legacy_files)
  for i in "${!PRIVATE_PATHS[@]}"; do
    p=${PRIVATE_PATHS[$i]#./}
    p=${p%/}
    PRIVATE_PATHS[i]=$p
    if ! printf '%s\n' "$all" | grep -qxF -e "$p" && ! printf '%s\n' "$all" | grep -qF -e "$p/"; then
      echo "Error: --private '$p' matches no legacy file." >&2
      exit 1
    fi
  done
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

# tracked | untracked | modified | no-git. An ignored file counts as untracked.
git_state() {
  if [ -z "$GIT_ROOT" ]; then echo "no-git"; return; fi
  if ! git -C "$VAULT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; then
    echo "untracked"
  elif [ -n "$(git -C "$VAULT" status --porcelain=v1 -- "$1" 2>/dev/null)" ]; then
    echo "modified"
  else
    echo "tracked"
  fi
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

# Why a legacy file must stay out of Git, or nothing when Git may keep it.
private_reason() {
  local rel=$1 state=$2 p
  case "$state" in no-git|untracked|modified) echo "$state"; return ;; esac
  if is_sensitive "$rel"; then echo "sensitive"; return; fi
  for p in ${PRIVATE_PATHS[@]+"${PRIVATE_PATHS[@]}"}; do
    case "$rel" in "$p"|"$p"/*) echo "requested"; return ;; esac
  done
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

# Delete empty directories under a path, never anything with content.
prune_empty_dirs() {
  if [ -d "$1" ]; then
    find "$1" -depth -type d -empty -delete 2>/dev/null || true
  fi
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
  check_private_paths
  CURATED=$(curated_notes)
  local files
  files=$(legacy_files)

  if [ "$FORMAT" = "tsv" ]; then
    printf 'path\tkind\tgit_state\tinbound_links\tsensitive\tarchive_to\tdescription\n'
    [ -z "$files" ] && return 0
    while IFS= read -r rel; do
      local links sens state reason dest=git
      links=$(inbound_links "$rel" | wc -l | tr -d ' ')
      if is_sensitive "$rel"; then sens=yes; else sens=no; fi
      state=$(git_state "$rel")
      reason=$(private_reason "$rel" "$state")
      [ -n "$reason" ] && dest="private:$reason"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$(kind_of "$rel")" "$state" \
        "$links" "$sens" "$dest" "$(describe "$rel")"
    done <<<"$files"
    return 0
  fi

  echo "Agent-memory inventory (read-only)"
  echo "Vault: $VAULT"
  echo "Git:   ${GIT_ROOT:-not a Git repository}"
  echo ""

  if [ -f "$VAULT/$ARCHIVE_REL/$MANIFEST_NAME" ]; then
    echo "A Git archive already exists at $ARCHIVE_REL/. Use 'restore' to reverse it."
    echo ""
  fi

  if [ -z "$files" ]; then
    echo "No legacy agent-memory content found."
    echo ""
    echo "Legacy hooks:"
    report_hooks
    return 0
  fi

  local rules=0 logs=0 other=0 private=0 sensitive=0 referenced=0
  local section_rules="" section_logs="" section_other="" section_links="" section_sens="" section_private=""
  while IFS= read -r rel; do
    local kind state desc links reason
    kind=$(kind_of "$rel")
    state=$(git_state "$rel")
    desc=$(describe "$rel")
    links=$(inbound_links "$rel")
    reason=$(private_reason "$rel" "$state")
    if [ -n "$reason" ]; then
      private=$((private + 1))
      section_private+="  [$reason] $rel"$'\n'
    fi
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
  echo "Bound for the private archive, outside Git: $private"
  if [ "$private" -gt 0 ]; then
    echo "  Do not commit these. archive moves them to --private-dir. A file that"
    echo "  Git already tracks stays in earlier commits, so rotate any credential"
    echo "  it holds. Name more files or folders with --private PATH."
    printf '%s' "$section_private"
  fi
  echo ""
  echo "Legacy hooks:"
  report_hooks
  echo ""
  local example_dir
  example_dir="$HOME/agent-memory-archive/$(basename "$VAULT")"
  echo "Next steps:"
  echo "  1. Promote any knowledge worth keeping with the librarian's promotion"
  echo "     workflow (references/librarian/knowledge-promotion.md)."
  echo "  2. Preview the archive:  $0 archive --vault \"$VAULT\" --private-dir $example_dir"
  echo "  3. Apply it:             add --apply to the same command"
}

cmd_archive() {
  resolve_vault
  resolve_private_dir
  check_private_paths
  local dest="$VAULT/$ARCHIVE_REL"

  local roots files root_list=()
  roots=$(present_roots)
  if [ -z "$roots" ]; then
    echo "No legacy agent-memory content in scope '$SCOPE'. Nothing to archive."
    return 0
  fi
  while IFS= read -r rel; do root_list+=("$rel"); done <<<"$roots"
  files=$(legacy_files "${root_list[@]}")

  # Sort every file into the Git archive or the private archive.
  local git_files=() private_files=() private_reasons=() private_states=()
  local rel state reason
  while IFS= read -r rel; do
    state=$(git_state "$rel")
    reason=$(private_reason "$rel" "$state")
    if [ -n "$reason" ]; then
      private_files+=("$rel"); private_reasons+=("$reason"); private_states+=("$state")
    else
      git_files+=("$rel")
    fi
  done <<<"$files"

  local blocked=0
  if [ ${#private_files[@]} -gt 0 ] && [ -z "$PRIVATE_DIR" ]; then
    echo "Refused: ${#private_files[@]} legacy files must stay out of Git, and no --private-dir" >&2
    echo "was given. Pass a folder outside every Git repository, for example:" >&2
    echo "  --private-dir $HOME/agent-memory-archive/$(basename "$VAULT")" >&2
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

  for rel in ${git_files[@]+"${git_files[@]}"}; do
    if [ -e "$dest/$rel" ]; then
      echo "Refused: $dest/$rel already exists." >&2
      blocked=1
    fi
  done
  if [ -n "$PRIVATE_DIR" ]; then
    for rel in ${private_files[@]+"${private_files[@]}"}; do
      if [ -e "$PRIVATE_DIR/$rel" ]; then
        echo "Refused: $PRIVATE_DIR/$rel already exists." >&2
        blocked=1
      fi
    done
  fi

  local i
  echo "Archive plan for $VAULT (scope: $SCOPE)"
  echo "Keep in Git: ${#git_files[@]} files, moved with git mv to $ARCHIVE_REL/"
  for rel in ${git_files[@]+"${git_files[@]}"}; do echo "  $rel"; done
  echo "Move out of Git: ${#private_files[@]} files, to ${PRIVATE_DIR:-the --private-dir}"
  for i in ${private_files[@]+"${!private_files[@]}"}; do
    echo "  [${private_reasons[$i]}] ${private_files[$i]}"
  done
  echo "Note content is not modified."
  [ -n "$linked" ] && echo "Inbound links that will break: $(printf '%s' "$linked" | wc -l | tr -d ' ')"

  if [ "$blocked" = "1" ]; then
    exit 2
  fi
  if [ "$APPLY" != "1" ]; then
    echo ""
    echo "Dry run. Re-run with --apply to perform the move."
    return 0
  fi

  # Moving files out of the repository needs a second, explicit yes.
  if [ ${#private_files[@]} -gt 0 ] && [ "$ASSUME_YES" != "1" ]; then
    if [ ! -t 0 ]; then
      echo "Refused: moving files out of Git needs confirmation. Run in a terminal, or pass --yes." >&2
      exit 2
    fi
    local answer=""
    printf 'Move %s files out of the vault to %s? Type yes to continue: ' \
      "${#private_files[@]}" "$PRIVATE_DIR"
    read -r answer || true
    if [ "$answer" != "yes" ]; then
      echo "Cancelled. Nothing moved."
      exit 2
    fi
  fi

  if [ ${#git_files[@]} -gt 0 ]; then
    mkdir -p "$dest"
    local manifest="$dest/$MANIFEST_NAME"
    # Append, so separately archived scopes share one manifest and one restore.
    if [ ! -f "$manifest" ]; then
      printf '# Legacy agent memory archived by scripts/migrate-agent-memory.sh\n' >"$manifest"
      printf '# kind\tsha256\tpath\n' >>"$manifest"
    fi
    for rel in "${git_files[@]}"; do
      printf 'file\t%s\t%s\n' "$(sha256 "$VAULT/$rel")" "$rel" >>"$manifest"
    done
    for rel in "${git_files[@]}"; do
      mkdir -p "$(dirname "$dest/$rel")"
      git -C "$VAULT" mv -- "$rel" "$ARCHIVE_REL/$rel"
    done
    git -C "$VAULT" add -- "$ARCHIVE_REL/$MANIFEST_NAME"

    # Verify every file arrived unchanged before reporting success.
    local bad=0 kind hash path
    while IFS=$'\t' read -r kind hash path; do
      [ "$kind" = "file" ] || continue
      [ -e "$dest/$path" ] || continue
      if [ "$(sha256 "$dest/$path")" != "$hash" ]; then
        echo "Error: $path changed during the move." >&2
        bad=1
      fi
    done <"$manifest"
    [ "$bad" = "0" ] || exit 1
  fi

  local untracked_from_git=()
  if [ ${#private_files[@]} -gt 0 ]; then
    # Only the owner can read the private archive.
    local old_umask
    old_umask=$(umask)
    umask 077
    mkdir -p "$PRIVATE_DIR"
    chmod 700 "$PRIVATE_DIR"
    local pmanifest="$PRIVATE_DIR/$PRIVATE_MANIFEST_NAME"
    if [ ! -f "$pmanifest" ]; then
      printf '# Legacy agent memory kept out of Git by scripts/migrate-agent-memory.sh\n' >"$pmanifest"
      printf '# vault\t%s\n' "$VAULT" >>"$pmanifest"
      printf '# kind\tsha256\tgit_state\treason\tpath\n' >>"$pmanifest"
    fi
    local hash copy
    for i in "${!private_files[@]}"; do
      rel=${private_files[$i]}
      copy="$PRIVATE_DIR/$rel"
      hash=$(sha256 "$VAULT/$rel")
      mkdir -p "$(dirname "$copy")"
      cp -p "$VAULT/$rel" "$copy"
      if [ "$(sha256 "$copy")" != "$hash" ]; then
        rm -f "$copy"
        echo "Error: the copy of $rel does not match the original. It was left in place." >&2
        exit 1
      fi
      # Record the copy before the original goes, so restore can always find it.
      printf 'file\t%s\t%s\t%s\t%s\n' "$hash" "${private_states[$i]}" "${private_reasons[$i]}" "$rel" >>"$pmanifest"
      case "${private_states[$i]}" in
        tracked|modified)
          git -C "$VAULT" rm -q --cached -f -- "$rel"
          untracked_from_git+=("$rel") ;;
      esac
      rm -f "$VAULT/$rel"
    done
    umask "$old_umask"
  fi

  for rel in "${root_list[@]}"; do prune_empty_dirs "$VAULT/$rel"; done

  echo ""
  if [ ${#git_files[@]} -gt 0 ]; then
    echo "Moved ${#git_files[@]} files to $ARCHIVE_REL/ and staged the move."
  fi
  if [ ${#private_files[@]} -gt 0 ]; then
    echo "Moved ${#private_files[@]} files to $PRIVATE_DIR. Checksums: $PRIVATE_DIR/$PRIVATE_MANIFEST_NAME"
    echo "That folder is not backed up by Git. Back it up yourself or delete it when you are done."
  fi
  if [ ${#untracked_from_git[@]} -gt 0 ]; then
    echo "Staged the removal of ${#untracked_from_git[@]} files Git tracked. Earlier commits still hold"
    echo "them, so rotate any credential they contain. Rewriting history is a separate step."
  fi
  if [ -n "$GIT_ROOT" ]; then
    echo "Review with 'git -C \"$VAULT\" status', then commit, e.g.:"
    echo "  git -C \"$VAULT\" commit -m \"Archive legacy agent memory\""
  fi
  echo "Undo with: $0 restore --vault \"$VAULT\"${PRIVATE_DIR:+ --private-dir \"$PRIVATE_DIR\"} --apply"
  echo "The next commit's index hook drops the archived notes from search."
}

cmd_restore() {
  resolve_vault
  resolve_private_dir
  local dest="$VAULT/$ARCHIVE_REL"
  local manifest="$dest/$MANIFEST_NAME"
  local pmanifest="${PRIVATE_DIR:+$PRIVATE_DIR/$PRIVATE_MANIFEST_NAME}"
  local have_git=0 have_private=0
  [ -f "$manifest" ] && have_git=1
  [ -n "$pmanifest" ] && [ -f "$pmanifest" ] && have_private=1
  if [ "$have_git" = "0" ] && [ "$have_private" = "0" ]; then
    echo "No archive manifest at $manifest${pmanifest:+ or $pmanifest}. Nothing to restore."
    [ -z "$PRIVATE_DIR" ] && echo "Pass --private-dir to restore files kept out of Git."
    return 0
  fi
  if [ "$have_git" = "1" ] && [ -z "$GIT_ROOT" ]; then
    echo "Refused: $VAULT is not inside a Git repository, so the Git archive cannot be moved back." >&2
    exit 2
  fi

  local kind hash state reason path blocked=0
  echo "Restore plan for $VAULT"
  if [ "$have_git" = "1" ]; then
    while IFS=$'\t' read -r kind hash path; do
      [ "$kind" = "file" ] || continue
      echo "  git mv $ARCHIVE_REL/$path -> $path"
      if [ -e "$VAULT/$path" ]; then echo "Refused: $VAULT/$path already exists." >&2; blocked=1; fi
      if [ ! -e "$dest/$path" ]; then echo "Refused: $dest/$path is missing from the archive." >&2; blocked=1; fi
    done <"$manifest"
  fi
  if [ "$have_private" = "1" ]; then
    while IFS=$'\t' read -r kind hash state reason path; do
      [ "$kind" = "file" ] || continue
      echo "  copy $PRIVATE_DIR/$path -> $path"
      if [ -e "$VAULT/$path" ]; then echo "Refused: $VAULT/$path already exists." >&2; blocked=1; fi
      if [ ! -e "$PRIVATE_DIR/$path" ]; then echo "Refused: $PRIVATE_DIR/$path is missing from the archive." >&2; blocked=1; fi
    done <"$pmanifest"
  fi
  [ "$blocked" = "0" ] || exit 2

  if [ "$APPLY" != "1" ]; then
    echo ""
    echo "Dry run. Re-run with --apply to perform the move."
    return 0
  fi

  local bad=0
  if [ "$have_git" = "1" ]; then
    while IFS=$'\t' read -r kind hash path; do
      [ "$kind" = "file" ] || continue
      mkdir -p "$(dirname "$VAULT/$path")"
      git -C "$VAULT" mv -- "$ARCHIVE_REL/$path" "$path"
      if [ "$(sha256 "$VAULT/$path")" != "$hash" ]; then
        echo "Error: $path does not match its archived checksum." >&2
        bad=1
      fi
    done <"$manifest"
    [ "$bad" = "0" ] || exit 1
    git -C "$VAULT" rm -q --cached -- "$ARCHIVE_REL/$MANIFEST_NAME" 2>/dev/null || true
    rm -f "$manifest"
    prune_empty_dirs "$VAULT/.archive"
  fi

  local was_tracked=()
  if [ "$have_private" = "1" ]; then
    while IFS=$'\t' read -r kind hash state reason path; do
      [ "$kind" = "file" ] || continue
      mkdir -p "$(dirname "$VAULT/$path")"
      cp -p "$PRIVATE_DIR/$path" "$VAULT/$path"
      if [ "$(sha256 "$VAULT/$path")" != "$hash" ]; then
        echo "Error: $path does not match its archived checksum. The archived copy was kept." >&2
        bad=1
        continue
      fi
      rm -f "$PRIVATE_DIR/$path"
      case "$state" in tracked|modified) was_tracked+=("$path") ;; esac
    done <"$pmanifest"
    [ "$bad" = "0" ] || exit 1
    rm -f "$pmanifest"
    prune_empty_dirs "$PRIVATE_DIR"
  fi

  echo ""
  echo "Restored. Files from the private archive are back in the vault but not staged."
  if [ ${#was_tracked[@]} -gt 0 ]; then
    echo "Git tracked these before the archive. To track them again:"
    for path in "${was_tracked[@]}"; do echo "  git -C \"$VAULT\" add -- \"$path\""; done
  fi
  if [ -n "$GIT_ROOT" ]; then
    echo "Review with 'git -C \"$VAULT\" status', then commit."
  fi
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
