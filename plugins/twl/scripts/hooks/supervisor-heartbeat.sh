#!/usr/bin/env bash
# PostToolUse hook: Write|Edit → heartbeat イベントをファイルに書き出す
# su-observer の Event Emission インフラ（#569）
set -uo pipefail

# stdin を消費
INPUT=$(cat 2>/dev/null || echo "")

# git リポジトリ内でなければ何もしない（git 外セッションは静かに終了）
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [[ -z "$GIT_COMMON_DIR" ]]; then
  exit 0
fi

# イベントディレクトリ（main/.supervisor/events/）
EVENTS_DIR="${GIT_COMMON_DIR}/../main/.supervisor/events"
mkdir -p "$EVENTS_DIR" 2>/dev/null || exit 0

# session_id 取得: stdin JSON → CLAUDE_SESSION_ID 環境変数 → PID フォールバック
SESSION_ID=""
if [[ -n "$INPUT" ]]; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
fi
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
fi

TIMESTAMP=$(date +%s 2>/dev/null || echo "0")
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "${PWD:-}")
if [[ -z "$CWD" ]]; then
  CWD="${PWD:-}"
fi

# アトミック書き込み（一時ファイル → mv）
TMP_FILE="${EVENTS_DIR}/heartbeat-${SESSION_ID}.tmp.$$"
TARGET_FILE="${EVENTS_DIR}/heartbeat-${SESSION_ID}"

printf '{"session_id":"%s","timestamp":%s,"cwd":"%s"}\n' \
  "$SESSION_ID" "$TIMESTAMP" "$CWD" > "$TMP_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }
mv "$TMP_FILE" "$TARGET_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }

exit 0
