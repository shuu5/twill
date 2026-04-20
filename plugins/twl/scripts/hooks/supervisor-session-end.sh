#!/usr/bin/env bash
# Stop hook: セッション終了シグナルをファイルに書き出す
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

TIMESTAMP=$(date +%s 2>/dev/null || echo "0")

# アトミック書き込み
TMP_FILE="${EVENTS_DIR}/session-end-${SESSION_ID}.tmp.$$"
TARGET_FILE="${EVENTS_DIR}/session-end-${SESSION_ID}"

printf '{"session_id":"%s","timestamp":%s,"event":"session-end"}\n' \
  "$SESSION_ID" "$TIMESTAMP" > "$TMP_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }
mv "$TMP_FILE" "$TARGET_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }

exit 0
