#!/usr/bin/env bash
# merge-gate-checkpoint-merge.sh - checkpoint 統合（merge-gate Step: checkpoint 統合）
#
# ac-verify / phase-review / specialist findings を統合した COMBINED_FINDINGS を stdout に出力。
#
# 引数: $1 = specialist FINDINGS JSON（省略時は '[]'）
# 呼び出し: COMBINED_FINDINGS=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-checkpoint-merge.sh" "$FINDINGS")

set -euo pipefail

FINDINGS="${1:-[]}"
AC_VERIFY_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step ac-verify --field findings 2>/dev/null || echo "[]")
POST_FIX_VERIFY_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step post-fix-verify --field findings 2>/dev/null || echo "")

# Issue #1703: ISSUE_NUMBER env var による per-Worker phase-review findings の isolation
# ISSUE_NUMBER 設定時は phase-review-{N}.json findings を優先（cross-pollution 防止）
_issue_number_args() {
  if [[ -n "${ISSUE_NUMBER:-}" ]]; then
    # bash 側 allowlist バリデーション（パストラバーサル防止、Issue #1703 security fix）
    if [[ ! "${ISSUE_NUMBER}" =~ ^[1-9][0-9]{0,6}$ ]]; then
      return 0  # 不正値は無視して shared checkpoint を使う（フォールバック）
    fi
    echo "--issue-number ${ISSUE_NUMBER}"
  fi
}

if [[ -n "$POST_FIX_VERIFY_FINDINGS" ]]; then
  jq -s 'add' <(echo "$FINDINGS") <(echo "$AC_VERIFY_FINDINGS") <(echo "$POST_FIX_VERIFY_FINDINGS")
else
  PHASE_REVIEW_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field findings $(_issue_number_args) 2>/dev/null || echo "[]")
  jq -s 'add' <(echo "$FINDINGS") <(echo "$AC_VERIFY_FINDINGS") <(echo "$PHASE_REVIEW_FINDINGS")
fi
