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
PHASE_REVIEW_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field findings 2>/dev/null || echo "[]")
jq -s 'add' <(echo "$FINDINGS") <(echo "$AC_VERIFY_FINDINGS") <(echo "$PHASE_REVIEW_FINDINGS")
