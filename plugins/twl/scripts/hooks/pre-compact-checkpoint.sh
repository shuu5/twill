#!/usr/bin/env bash
# PreCompact hook: compaction 前に chain 進行位置と重要変数を保存
#
# compaction は observability-only でブロック不可。
# current_step を issue-{N}.json に書き込み、重要変数を context.md に追記する。
# エラーが発生してもワークフローを停止しない（|| true / exit 0 保証）
set -uo pipefail

# stdin を消費（PreCompact は stdin に JSON を渡す可能性あり）
cat > /dev/null 2>&1 || true

# AUTOPILOT_DIR 未設定 or 空 → 何もしない
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# AUTOPILOT_DIR が実在するディレクトリでなければ無視
if [[ ! -d "${AUTOPILOT_DIR}" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/python-env.sh
source "${SCRIPTS_ROOT}/lib/python-env.sh"

# ── 実行中 Issue の特定 ──
ISSUE_NUM=""
# issues/ サブディレクトリを検索（state-write.sh のパス形式に合わせる）
for state_file in "${AUTOPILOT_DIR}"/issues/issue-*.json; do
  if [[ -f "$state_file" ]]; then
    STATUS=$(jq -r '.status // ""' "$state_file" 2>/dev/null || echo "")
    if [[ "$STATUS" == "running" ]]; then
      ISSUE_NUM=$(basename "$state_file" | grep -Eo '[0-9]+' | head -1)
      break
    fi
  fi
done

if [[ -z "$ISSUE_NUM" ]]; then
  # 実行中 Issue なし → 何もしない
  exit 0
fi

# ── 現在の current_step を取得 ──
CURRENT_STEP=""
CURRENT_STEP="$(python3 -m twl.autopilot.state read \
  --type issue --issue "$ISSUE_NUM" --field current_step \
  2>/dev/null || echo "")"

if [[ -z "$CURRENT_STEP" ]]; then
  # current_step 未設定 → 書き込み不要
  exit 0
fi

# 値の安全性を確認（英数字とハイフンのみ許可）
if [[ ! "$CURRENT_STEP" =~ ^[a-z0-9-]+$ ]]; then
  # 不正な値は書き込まずスキップ
  exit 0
fi

# ── current_step を再書き込み（compaction 前確定保存） ──
# 冪等: 既に同じ値でも書き込む（compaction サマリへの反映を確実にする）
python3 -m twl.autopilot.state write \
  --type issue --issue "$ISSUE_NUM" --role worker \
  --set "current_step=${CURRENT_STEP}" 2>/dev/null || true

# ── 重要変数を context.md に追記 ──
CONTEXT_DIR="${AUTOPILOT_DIR}/issues"
CONTEXT_FILE="${CONTEXT_DIR}/issue-${ISSUE_NUM}-context.md"
mkdir -p "$CONTEXT_DIR" 2>/dev/null || true

# state から重要変数を取得
PR_NUMBER="$(python3 -m twl.autopilot.state read \
  --type issue --issue "$ISSUE_NUM" --field pr_number \
  2>/dev/null || echo "")"
MODE="$(python3 -m twl.autopilot.state read \
  --type issue --issue "$ISSUE_NUM" --field mode \
  2>/dev/null || echo "")"
COMPACT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"

{
  echo ""
  echo "## compaction_checkpoint (${COMPACT_AT})"
  echo "current_step: ${CURRENT_STEP}"
  [[ -n "$PR_NUMBER" ]] && echo "pr_number: ${PR_NUMBER}"
  [[ -n "$MODE" ]] && echo "mode: ${MODE}"
} >> "$CONTEXT_FILE" 2>/dev/null || true

exit 0
