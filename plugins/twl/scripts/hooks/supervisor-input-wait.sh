#!/usr/bin/env bash
# PreToolUse hook: AskUserQuestion → input-wait イベントをファイルに書き出す
# su-observer の Event Emission インフラ（#569）
set -uo pipefail

# stdin を消費
INPUT=$(cat 2>/dev/null || echo "")

# bare repo 構造（main/ 存在）でなければ no-op
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [[ -z "$GIT_COMMON_DIR" ]]; then
  exit 0
fi
if [[ ! -d "${GIT_COMMON_DIR}/../main" ]]; then
  exit 0
fi

# TEST-ONLY: TWL_SUPERVISOR_EVENTS_DIR は test sandbox 専用。production で set しないこと
EVENTS_DIR="${TWL_SUPERVISOR_EVENTS_DIR:-${GIT_COMMON_DIR}/../main/.supervisor/events}"
mkdir -p "$EVENTS_DIR" 2>/dev/null || exit 0

# session_id 取得
SESSION_ID=""
if [[ -n "$INPUT" ]]; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
fi
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
fi

_SESSION_ID_RAW="$SESSION_ID"
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-')
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="$$"
fi
if [[ "$SESSION_ID" != "$_SESSION_ID_RAW" ]]; then
  printf '[supervisor-hook][warn] SESSION_ID sanitized (hook=%s pid=%s)\n' \
    "$(basename "$0")" "$$" >&2
fi

TIMESTAMP=$(date +%s 2>/dev/null || echo "0")

# アトミック書き込み
TMP_FILE="${EVENTS_DIR}/input-wait-${SESSION_ID}.tmp.$$"
TARGET_FILE="${EVENTS_DIR}/input-wait-${SESSION_ID}"

printf '{"session_id":"%s","timestamp":%s,"event":"input-wait"}\n' \
  "$SESSION_ID" "$TIMESTAMP" > "$TMP_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }
mv "$TMP_FILE" "$TARGET_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }

exit 0
