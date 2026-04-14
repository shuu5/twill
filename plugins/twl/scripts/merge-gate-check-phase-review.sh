#!/usr/bin/env bash
# merge-gate-check-phase-review.sh - phase-review 必須チェック（merge-gate Step: phase-review 必須チェック）
#
# phase-review checkpoint の存在を確認し、不在の場合は REJECT を返す（defense-in-depth, Issue #439）。
# scope/direct または quick ラベルがある Issue はスキップ。
#
# 引数: [--force]  → phase-review 不在時に WARNING で続行
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-phase-review.sh" [--force]

set -euo pipefail

FORCE="${1:-}"

ISSUE_NUM=$(source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo "")
ISSUE_LABELS=$(gh issue view "$ISSUE_NUM" --json labels -q '[.labels[].name]' 2>/dev/null || echo "[]")
SKIP_PHASE_REVIEW=false
while IFS= read -r label; do
  [[ "$label" == "scope/direct" || "$label" == "quick" ]] && SKIP_PHASE_REVIEW=true && break
done < <(echo "$ISSUE_LABELS" | jq -r '.[]')

PHASE_REVIEW_STATUS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field status 2>/dev/null || echo "MISSING")

if [[ "$SKIP_PHASE_REVIEW" == "true" ]]; then
  echo "phase-review チェックをスキップ（scope/direct / quick ラベル付き Issue）"
  exit 0
fi

if [[ "$PHASE_REVIEW_STATUS" == "MISSING" ]]; then
  if [[ "$FORCE" == "--force" ]]; then
    echo "WARNING: phase-review checkpoint が不在です（--force により続行）" >&2
    exit 0
  else
    echo "REJECT: phase-review checkpoint が不在です。specialist review を実行してください" >&2
    exit 1
  fi
fi
