#!/usr/bin/env bash
# session-atomic-write.sh - Atomic RMW helper for session.json using flock(8) advisory lock
#
# Usage: session-atomic-write.sh <session_file> [jq_args...] <jq_filter>
#   <session_file>  : path to session.json (input + output)
#   [jq_args]      : jq options, e.g. --arg key val --argjson phase 1
#   <jq_filter>    : jq filter expression (last positional arg)
#
# Example:
#   session-atomic-write.sh "$SESSION_STATE_FILE" \
#     --arg phase "$P" --arg results "$R" \
#     '.retrospectives += [{"phase": ($phase | tonumber), "results": $results}]'
#
# Portability: Linux (util-linux flock). macOS requires Homebrew util-linux or alternative.
# See ADR-028 for strategy rationale.
#
# Exit codes: 0=success (or file not found, skip), 1=jq error or lock timeout
set -euo pipefail

SESSION_FILE="$1"
shift

if [[ ! -f "$SESSION_FILE" ]]; then
  echo "⚠️ session-atomic-write: $SESSION_FILE が見つかりません（スキップ）" >&2
  exit 0
fi

LOCK_FILE="${SESSION_FILE}.lock"

(
  flock -x -w 10 9 || { echo "ERROR: flock タイムアウト (10s): $SESSION_FILE" >&2; exit 1; }
  TMP=$(mktemp)
  if jq "$@" "$SESSION_FILE" > "$TMP"; then
    mv "$TMP" "$SESSION_FILE"
  else
    rm -f "$TMP"
    exit 1
  fi
) 9>>"$LOCK_FILE"
