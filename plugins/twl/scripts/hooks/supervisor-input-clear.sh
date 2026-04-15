#!/usr/bin/env bash
# PostToolUse hook: AskUserQuestion → input-wait ファイルを削除（入力待ち解消）
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

# イベントディレクトリ
EVENTS_DIR="${AUTOPILOT_DIR}/../.supervisor/events"

# session_id 取得
SESSION_ID=""
if [[ -n "$INPUT" ]]; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
fi
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
fi

# input-wait ファイルを削除（存在しなければ何もしない）
TARGET_FILE="${EVENTS_DIR}/input-wait-${SESSION_ID}"
rm -f "$TARGET_FILE" 2>/dev/null || true

exit 0
