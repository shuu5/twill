#!/usr/bin/env bash
# merge-gate-cross-pr-ac.sh - Cross-PR AC 検証（merge-gate Step: Cross-PR AC 検証）
#
# implementation_pr が設定されている場合、マージコミットを取得して checkpoint に記録する。
# retroactive DeltaSpec 対応。
#
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-cross-pr-ac.sh"

set -euo pipefail

ISSUE_NUM=$(source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo "")
IMPL_PR=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE_NUM" --field implementation_pr 2>/dev/null || echo "")
if [[ -n "$IMPL_PR" && "$IMPL_PR" != "null" ]]; then
  MERGE_COMMIT=$(gh pr view "$IMPL_PR" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null || echo "")
  if [[ -n "$MERGE_COMMIT" ]]; then
    echo "ℹ️ Cross-PR AC 検証: implementation_pr=#${IMPL_PR} (merge commit: ${MERGE_COMMIT})"
    python3 -m twl.autopilot.checkpoint write --step merge-gate --extra "verified_via_pr=$IMPL_PR" --extra "verified_via_commit=$MERGE_COMMIT" 2>/dev/null || true
  else
    echo "⚠️ WARN: implementation_pr=#${IMPL_PR} のマージコミットを取得できませんでした"
  fi
fi
