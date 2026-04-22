#!/usr/bin/env bash
# session-end-pitfall-append.sh
# Appends new observer-pitfall entries to pitfalls-catalog.md at session end.
#
# Usage:
#   echo "pitfall text" | session-end-pitfall-append.sh [OPTIONS]
#   session-end-pitfall-append.sh [OPTIONS] -- "entry1" "entry2"
#
# Options:
#   --dry-run           Write diff to pending file; do not modify catalog
#   --catalog <path>    Override catalog path (default: auto-detect from repo)
#   --supervisor-dir <path>  Override .supervisor dir (default: auto-detect)
#   --hash <hash>       doobidoo hash to annotate the entry
#   --session <id>      Session ID for annotation
#
# Stdin: one pitfall entry per line (used when no '--' args are given)
# '--' separates options from entry strings passed as positional args
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
CATALOG_PATH=""
SUPERVISOR_DIR=""
ENTRY_HASH=""
SESSION_ID=""
POSITIONAL_ENTRIES=()
PARSE_OPTS=true
MAX_LINES=200

while [[ $# -gt 0 ]]; do
  if [[ "$PARSE_OPTS" == true ]]; then
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --catalog) CATALOG_PATH="$2"; shift 2 ;;
      --supervisor-dir) SUPERVISOR_DIR="$2"; shift 2 ;;
      --hash) ENTRY_HASH="$2"; shift 2 ;;
      --session) SESSION_ID="$2"; shift 2 ;;
      --) PARSE_OPTS=false; shift ;;
      --*) echo "[pitfall-append][warn] Unknown option: $1" >&2; shift ;;
      *) POSITIONAL_ENTRIES+=("$1"); shift ;;
    esac
  else
    POSITIONAL_ENTRIES+=("$1"); shift
  fi
done

# Auto-detect repo root from bare repo structure
_detect_repo_main() {
  local common_dir
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
  if [[ -n "$common_dir" && -d "${common_dir}/../main" ]]; then
    echo "${common_dir}/../main"
  else
    echo ""
  fi
}

REPO_MAIN="${TWL_REPO_MAIN:-$(_detect_repo_main)}"

# Resolve catalog path
if [[ -z "$CATALOG_PATH" ]]; then
  if [[ -n "$REPO_MAIN" ]]; then
    CATALOG_PATH="${REPO_MAIN}/plugins/twl/skills/su-observer/refs/pitfalls-catalog.md"
  else
    echo "[pitfall-append][error] Cannot detect repo root; use --catalog" >&2
    exit 1
  fi
fi

# Resolve supervisor dir
if [[ -z "$SUPERVISOR_DIR" ]]; then
  if [[ -n "$REPO_MAIN" ]]; then
    SUPERVISOR_DIR="${REPO_MAIN}/.supervisor"
  else
    SUPERVISOR_DIR="$(pwd)/.supervisor"
  fi
fi

PENDING_DIFF="${SUPERVISOR_DIR}/pending-pitfall-append.diff"
ARCHIVE_PATH="$(dirname "$CATALOG_PATH")/pitfalls-archive.md"

# Collect entries
ENTRIES=()
if [[ ${#POSITIONAL_ENTRIES[@]} -gt 0 ]]; then
  ENTRIES=("${POSITIONAL_ENTRIES[@]}")
elif [[ ! -t 0 ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && ENTRIES+=("$line")
  done
fi

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
  echo "[pitfall-append] No entries to append." >&2
  exit 0
fi

if [[ ! -f "$CATALOG_PATH" ]]; then
  echo "[pitfall-append][error] Catalog not found: $CATALOG_PATH" >&2
  exit 1
fi

# Format entries
TODAY=$(date +%Y-%m-%d 2>/dev/null || echo "unknown")
HASH_ANNOTATION=""
[[ -n "$ENTRY_HASH" ]] && HASH_ANNOTATION=" hash=${ENTRY_HASH}"
SESSION_ANNOTATION=""
[[ -n "$SESSION_ID" ]] && SESSION_ANNOTATION=" session=${SESSION_ID}"

_format_entries() {
  local annotation="<!-- auto-append: date=${TODAY}${HASH_ANNOTATION}${SESSION_ANNOTATION} -->"
  echo "$annotation"
  for entry in "${ENTRIES[@]}"; do
    printf -- '- [auto] %s\n' "$entry"
  done
}

FORMATTED="$(_format_entries)"

if [[ "$DRY_RUN" == true ]]; then
  mkdir -p "$SUPERVISOR_DIR"
  {
    printf '--- a/pitfalls-catalog.md\n'
    printf '+++ b/pitfalls-catalog.md (pending)\n'
    printf '@@ pending auto-append @@\n'
    while IFS= read -r line; do
      printf '+%s\n' "$line"
    done <<< "$FORMATTED"
  } > "$PENDING_DIFF"
  printf '[pitfall-append] dry-run: diff written to %s\n' "$PENDING_DIFF"
  exit 0
fi

# Check line count; archive if needed before appending
CURRENT_LINES=$(wc -l < "$CATALOG_PATH")
NEW_LINES_COUNT=$(printf '%s\n' "$FORMATTED" | wc -l)
PROJECTED=$((CURRENT_LINES + NEW_LINES_COUNT))

if [[ $PROJECTED -gt $MAX_LINES ]]; then
  # Move content from line 10 to line $((MAX_LINES / 2)) into archive to free space
  ARCHIVE_END=$((MAX_LINES / 2))
  ARCHIVE_CONTENT=$(sed -n "10,${ARCHIVE_END}p" "$CATALOG_PATH")
  TMP_CAT=$(mktemp)
  {
    head -n 9 "$CATALOG_PATH"
    tail -n "+$((ARCHIVE_END + 1))" "$CATALOG_PATH"
  } > "$TMP_CAT"
  mv "$TMP_CAT" "$CATALOG_PATH"
  {
    [[ -f "$ARCHIVE_PATH" ]] && cat "$ARCHIVE_PATH"
    echo ""
    printf '## Archived %s\n' "$TODAY"
    printf '%s\n' "$ARCHIVE_CONTENT"
  } > "${ARCHIVE_PATH}.tmp"
  mv "${ARCHIVE_PATH}.tmp" "$ARCHIVE_PATH"
  echo "[pitfall-append] Archived old entries to $(basename "$ARCHIVE_PATH")"
fi

# Append entries at end of catalog
printf '\n%s\n' "$FORMATTED" >> "$CATALOG_PATH"
printf '[pitfall-append] Appended %d entries to catalog.\n' "${#ENTRIES[@]}"
