#!/usr/bin/env bash
# spec-review-session-init.sh — spec-review セッション state を初期化する
#
# 使用方法: spec-review-session-init.sh <total>
#   total: レビュー対象 Issue 数
#
# セッション state ファイル: /tmp/.spec-review-session-{hash}.json
#   hash: CLAUDE_PROJECT_ROOT または PWD から cksum で算出
# 競合制御: flock を使用

set -uo pipefail

TOTAL="${1:-}"
if [[ -z "$TOTAL" ]]; then
  echo "Usage: spec-review-session-init.sh <total>" >&2
  exit 1
fi

# total が正の整数か検証
if ! [[ "$TOTAL" =~ ^[0-9]+$ ]] || [[ "$TOTAL" -eq 0 ]]; then
  echo "Error: total must be a positive integer, got: $TOTAL" >&2
  exit 1
fi

# hash 算出（プロジェクトルートまたは PWD から）
HASH=$(printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}')
STATE_FILE="/tmp/.spec-review-session-${HASH}.json"
LOCK_FILE="/tmp/.spec-review-session-${HASH}.lock"

# flock 付きで state ファイルを書き込み（既存があれば上書き初期化）
{
  flock -w 5 9 || { echo "Error: failed to acquire lock on $LOCK_FILE" >&2; exit 1; }
  printf '{"total":%d,"completed":0,"issues":{}}\n' "$TOTAL" > "$STATE_FILE"
} 9>"$LOCK_FILE"

echo "✓ spec-review session initialized: total=${TOTAL}, state=${STATE_FILE}"
