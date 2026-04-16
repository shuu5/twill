#!/usr/bin/env bash
# PostToolUse Write|Edit hook: .explore/<N>/summary.md への書き込みを検知し
# gh issue comment で explore-summary リンクを追加する（#726）
set -uo pipefail

LOG_FILE="/tmp/explore-link-hook.log"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$LOG_FILE"
}

# stdin を消費
INPUT=$(cat 2>/dev/null || echo "")

# FILE_PATH 取得: env var 優先、stdin JSON フォールバック
FILE_PATH="${TOOL_INPUT_file_path:-}"
if [[ -z "$FILE_PATH" && -n "$INPUT" ]]; then
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
fi

# /.explore/<N>/summary.md パターンにマッチするか確認（スラッシュプレフィックス必須）
if [[ -z "$FILE_PATH" ]] || ! printf '%s' "$FILE_PATH" | grep -qE '/.explore/[0-9]+/summary\.md$'; then
  exit 0
fi

# Issue 番号を抽出
ISSUE_NUM=$(printf '%s' "$FILE_PATH" | sed -n 's|.*/.explore/\([0-9][0-9]*\)/summary\.md$|\1|p')
if [[ -z "$ISSUE_NUM" ]]; then
  exit 0
fi

# git リポジトリ内でなければ終了
if ! git rev-parse --git-common-dir &>/dev/null; then
  exit 0
fi

# gh コマンド確認
if ! command -v gh &>/dev/null; then
  log "WARNING: gh command not found"
  exit 0
fi

# 冪等性チェック: 既存の explore-summary リンクコメントを確認
EXISTING_COUNT=0
EXISTING_COUNT=$(gh issue view "$ISSUE_NUM" --json comments 2>>"$LOG_FILE" \
  | jq -r '[.comments[].body | select(contains("explore-summary linked:"))] | length' 2>>"$LOG_FILE") || true

if [[ "${EXISTING_COUNT:-0}" -gt 0 ]]; then
  log "WARNING: explore-summary already linked for Issue #${ISSUE_NUM} (check-then-act race condition possible)"
  exit 0
fi

# gh issue comment（stderr はログファイルに出力）
if ! gh issue comment "$ISSUE_NUM" --body "explore-summary linked: \`${FILE_PATH}\`" 2>>"$LOG_FILE"; then
  log "ERROR: failed to comment on Issue #${ISSUE_NUM}"
fi

exit 0
