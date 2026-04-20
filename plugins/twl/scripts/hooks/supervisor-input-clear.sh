#!/usr/bin/env bash
# PostToolUse hook: AskUserQuestion → input-wait ファイルを削除（入力待ち解消）
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
