#!/usr/bin/env bash
# post-skill-chain-nudge.sh - PostToolUse hook: Skill tool 完了後に chain 継続を stdout に注入する
# Issue #200: Autopilot Worker chain 遷移停止の機械的防止 (Layer 1)
#
# Claude Code の PostToolUse hook は stdin に JSON を渡す。
# 本スクリプトは stdout に出力することで LLM コンテキストに注入する。
# エラー時は stderr にログ出力し、必ず exit 0 で終了する（Worker を止めてはならない）。
# NOTE: set -euo pipefail は使用しない（exit 0 保証のため）。エラーは || true で吸収する。

# エラー時も exit 0 を保証する（Worker を止めてはならない）
trap 'exit 0' EXIT ERR

# stdin を読み捨て（パイプブロック防止）
INPUT=$(cat 2>/dev/null || true)

# --- Step 1: AUTOPILOT_DIR 未設定 → 通常利用に影響しない透過終了 ---
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# --- スクリプトディレクトリ解決 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/python-env.sh
source "${SCRIPTS_ROOT}/lib/python-env.sh"

# --- Step 2: state file ベースで Issue 番号を解決 ---
ISSUE_NUM=""
# shellcheck source=../resolve-issue-num.sh
source "${SCRIPTS_ROOT}/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num 2>/dev/null || true)

# 明示的な数値検証（Input Validation: シェルインジェクション防止）
if [[ -z "$ISSUE_NUM" || ! "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
  exit 0
fi

# --- Step 3: current_step を state-read.sh で取得 ---
CURRENT_STEP=""
CURRENT_STEP=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE_NUM" --field current_step 2>/dev/null || true)

if [[ -z "$CURRENT_STEP" ]]; then
  # current_step が空の場合は透過終了（chain 未開始）
  exit 0
fi

# --- Step 4: chain-runner.sh next-step で次ステップを機械的に決定 ---
NEXT_STEP=""
NEXT_STEP=$(bash "$SCRIPTS_ROOT/chain-runner.sh" next-step "$ISSUE_NUM" "$CURRENT_STEP" 2>/dev/null || true)

# --- Step 5: "done" または空 → 終了 ---
if [[ -z "$NEXT_STEP" || "$NEXT_STEP" == "done" ]]; then
  exit 0
fi

# --- Step 5.5: ワークフロー境界判定 ---
# chain-steps.sh の CHAIN_STEP_WORKFLOW / CHAIN_WORKFLOW_NEXT_SKILL を参照し、
# ワークフロー境界（例: ac-verify → all-pass-check ではなく pr-verify → pr-fix）を検出する
# shellcheck source=../chain-steps.sh
source "${SCRIPTS_ROOT}/chain-steps.sh" 2>/dev/null || true

CURRENT_WORKFLOW="${CHAIN_STEP_WORKFLOW[$CURRENT_STEP]:-}"
NEXT_WORKFLOW="${CHAIN_STEP_WORKFLOW[$NEXT_STEP]:-}"

if [[ -n "$CURRENT_WORKFLOW" && -n "$NEXT_WORKFLOW" && "$CURRENT_WORKFLOW" != "$NEXT_WORKFLOW" ]]; then
  # ワークフロー境界: 次の workflow skill を nudge
  NEXT_STEP="${CHAIN_WORKFLOW_NEXT_SKILL[$CURRENT_WORKFLOW]:-}"
  if [[ -z "$NEXT_STEP" ]]; then
    # ワークフロー末尾（pr-merge など）→ 終了
    exit 0
  fi
fi

# --- Step 6: サニタイズ（シェル/HTML インジェクション防止: 英数字・/:.-_ のみ許可） ---
SAFE_NEXT_STEP=$(printf '%s' "$NEXT_STEP" | tr -cd 'a-zA-Z0-9/:._-')

if [[ -z "$SAFE_NEXT_STEP" ]]; then
  printf 'post-skill-chain-nudge: next_step サニタイズ後に空になりました: %s\n' "$NEXT_STEP" >&2
  exit 0
fi

# --- Step 7: stdout に chain-continuation メッセージを出力（LLM コンテキスト注入） ---
printf '[chain-continuation] 次は /twl:%s を Skill tool で実行せよ。停止するな。\n' "$SAFE_NEXT_STEP"

# --- Step 8: last_hook_nudge_at タイムスタンプを issue-{N}.json に記録 ---
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
python3 -m twl.autopilot.state write \
  --type issue \
  --issue "$ISSUE_NUM" \
  --role worker \
  --set "last_hook_nudge_at=${NOW}" 2>/dev/null || true

exit 0
