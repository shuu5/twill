#!/usr/bin/env bash
# compaction-resume.sh - compaction 後の chain 復帰判定
#
# Usage: bash compaction-resume.sh <ISSUE_NUM> <step_id>
#
# 指定ステップが完了済みか（スキップ可能か）を exit code で返す:
#   exit 0 → 要実行（ステップを実行すること）
#   exit 1 → スキップ可（ステップは完了済み）
#
# 判定ロジック:
#   current_step = "X" のとき、X の実行が始まっている（完了保証なし）
#   query_step が X より前にある → 完了済み → exit 1（スキップ）
#   query_step が X 以降にある → 未完了 → exit 0（実行）
#
# 例:
#   current_step=board-status-update の場合
#     compaction-resume.sh 129 worktree-create → exit 1 (スキップ: worktree-create は完了済み)
#     compaction-resume.sh 129 board-status-update → exit 0 (実行: 途中の可能性あり)
#     compaction-resume.sh 129 change-propose → exit 0 (実行: 未到達)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =====================================================================
# chain ステップ順序定義（SSOT: scripts/chain-steps.sh）
# =====================================================================
# shellcheck source=./chain-steps.sh
source "${SCRIPT_DIR}/chain-steps.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <ISSUE_NUM> <step_id>

compaction 後の chain 復帰判定。

Arguments:
  ISSUE_NUM  Issue 番号（正の整数）
  step_id    判定するステップ名

Exit codes:
  0  要実行（ステップを実行すること）
  1  スキップ可（ステップは完了済み）
  2  エラー（引数不正、ファイル不在など）
EOF
}

# ── 引数チェック ──
if [[ $# -lt 2 ]]; then
  echo "ERROR: 引数が不足しています" >&2
  usage >&2
  exit 2
fi

ISSUE_NUM="$1"
QUERY_STEP="$2"

if [[ ! "$ISSUE_NUM" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: ISSUE_NUM は正の整数（1以上）を指定してください: $ISSUE_NUM" >&2
  exit 2
fi

if [[ ! "$QUERY_STEP" =~ ^[a-z0-9-]+$ ]]; then
  echo "ERROR: step_id に無効な文字が含まれています: $QUERY_STEP" >&2
  exit 2
fi

# ── is_quick チェック（QUICK_SKIP_STEPS に含まれるなら即スキップ）──
IS_QUICK="$(bash "$SCRIPT_DIR/state-read.sh" \
  --type issue \
  --issue "$ISSUE_NUM" \
  --field is_quick \
  2>/dev/null || echo "")"

if [[ "$IS_QUICK" == "true" ]]; then
  for skip_step in "${QUICK_SKIP_STEPS[@]}"; do
    if [[ "$QUERY_STEP" == "$skip_step" ]]; then
      exit 1
    fi
  done
fi

# ── current_step 取得 ──
CURRENT_STEP=""
CURRENT_STEP="$(bash "$SCRIPT_DIR/state-read.sh" \
  --type issue \
  --issue "$ISSUE_NUM" \
  --field current_step \
  2>/dev/null || echo "")"

if [[ -z "$CURRENT_STEP" ]]; then
  # current_step が未設定 → compaction 未発生 or 初回 → 要実行
  exit 0
fi

# ── step_id の順序インデックスを取得 ──
get_index() {
  local target="$1"
  local i=0
  for step in "${CHAIN_STEPS[@]}"; do
    if [[ "$step" == "$target" ]]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  echo "-1"
}

CURRENT_IDX="$(get_index "$CURRENT_STEP")"
QUERY_IDX="$(get_index "$QUERY_STEP")"

if [[ "$CURRENT_IDX" == "-1" ]]; then
  # current_step が不明なステップ → 安全側: 要実行
  exit 0
fi

if [[ "$QUERY_IDX" == "-1" ]]; then
  # query_step が不明なステップ → 安全側: 要実行
  exit 0
fi

# ── 判定 ──
# query_step が current_step より前にある → 完了済み → スキップ
if (( QUERY_IDX < CURRENT_IDX )); then
  exit 1
fi

# query_step が current_step と同じか後ろ → 要実行
exit 0
