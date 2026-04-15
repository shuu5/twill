#!/usr/bin/env bash
# PreToolUse hook: AskUserQuestion → input-wait イベントをファイルに書き出す
# su-observer の Event Emission インフラ（#569）
set -uo pipefail

# stdin を消費
INPUT=$(cat 2>/dev/null || echo "")

# AUTOPILOT_DIR 未設定 or 空 → 通常セッション、何もしない
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# AUTOPILOT_DIR が実在するディレクトリでなければ無視
if [[ ! -d "${AUTOPILOT_DIR}" ]]; then
  exit 0
fi

# イベントディレクトリ（main/.supervisor/events/）
EVENTS_DIR="${AUTOPILOT_DIR}/../.supervisor/events"
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
TMP_FILE="${EVENTS_DIR}/input-wait-${SESSION_ID}.tmp.$$"
TARGET_FILE="${EVENTS_DIR}/input-wait-${SESSION_ID}"

printf '{"session_id":"%s","timestamp":%s,"event":"input-wait"}\n' \
  "$SESSION_ID" "$TIMESTAMP" > "$TMP_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }
mv "$TMP_FILE" "$TARGET_FILE" 2>/dev/null || { rm -f "$TMP_FILE" 2>/dev/null; exit 0; }

exit 0
