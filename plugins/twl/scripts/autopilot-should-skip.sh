#!/bin/bash
# =============================================================================
# autopilot-should-skip.sh - 依存グラフベースの skip 判定
#
# Usage:
#   bash autopilot-should-skip.sh <plan.yaml> <issue_number>
#
# Exit codes:
#   0 = skip（依存先が fail/skipped、または未完了）
#   1 = 実行（依存先が全て done、または依存なし）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/python-env.sh
source "${SCRIPT_DIR}/lib/python-env.sh"

PLAN_FILE="${1:?Usage: $0 <plan.yaml> <issue_number>}"
ISSUE="${2:?Usage: $0 <plan.yaml> <issue_number>}"

# ISSUE 数値バリデーション
if ! [[ "$ISSUE" =~ ^[0-9]+$ ]]; then
  echo "Error: ISSUE must be a positive integer: $ISSUE" >&2
  exit 1
fi

# --- plan.yaml から依存先を取得 ---
# dependencies セクションから対象 Issue の依存先を抽出
DEPS=$(sed -n "/^dependencies:/,\$p" "$PLAN_FILE" \
  | sed -n "/^  ${ISSUE}:/,/^  [0-9]/p" \
  | grep -oP '  - \K\d+' || true)

# 依存なし → 実行
if [ -z "$DEPS" ]; then
  exit 1
fi

# --- 各依存先の状態をチェック（state-read.sh 経由） ---
for dep in $DEPS; do
  STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$dep" --field status 2>/dev/null || true)

  # done のみが「依存解決済み」— それ以外は全てスキップ
  if [ "$STATUS" != "done" ]; then
    exit 0
  fi
done

# 全依存先が done → 実行
exit 1
