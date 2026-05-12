#!/usr/bin/env bash
# merge-gate-check-phase-review.sh - phase-review 必須チェック（merge-gate Step: phase-review 必須チェック）
#
# phase-review checkpoint の存在を確認し、不在の場合は REJECT を返す（defense-in-depth, Issue #439）。
# findings に category=ac_missing の WARNING がある場合も REJECT する（Issue #1025）。
#
# 引数: [--force]  → phase-review 不在時に WARNING で続行
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-phase-review.sh" [--force]

set -euo pipefail

FORCE="${1:-}"

# Issue #1703: ISSUE_NUMBER env var による per-Worker checkpoint isolation
# ISSUE_NUMBER が設定されている場合は phase-review-{N}.json を優先参照し、
# 不在時は phase-review.json にフォールバックする（cross-pollution 防止）。
_issue_number_args() {
  if [[ -n "${ISSUE_NUMBER:-}" ]]; then
    echo "--issue-number ${ISSUE_NUMBER}"
  fi
}

PHASE_REVIEW_STATUS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field status $(_issue_number_args) 2>/dev/null || echo "MISSING")

if [[ "$PHASE_REVIEW_STATUS" == "MISSING" ]]; then
  if [[ "$FORCE" == "--force" ]]; then
    echo "WARNING: phase-review checkpoint が不在です（--force により続行）" >&2
    exit 0
  else
    echo "REJECT: phase-review checkpoint が不在です。specialist review を実行してください" >&2
    exit 1
  fi
fi

# Issue #1025: findings の category=ac_missing WARNING で merge をブロック
# Issue #1703: ISSUE_NUMBER が設定されている場合は per-issue ファイルを参照
_resolve_checkpoint_file() {
  local dir=""
  if [[ -n "${AUTOPILOT_DIR:-}" ]]; then
    dir="${AUTOPILOT_DIR}/checkpoints"
  else
    local root=""
    root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    dir="${root:+${root}/.autopilot/checkpoints}"
    dir="${dir:-.autopilot/checkpoints}"
  fi
  # per-issue ファイルが存在すればそちらを優先（Issue #1703）
  if [[ -n "${ISSUE_NUMBER:-}" && -f "${dir}/phase-review-${ISSUE_NUMBER}.json" ]]; then
    echo "${dir}/phase-review-${ISSUE_NUMBER}.json"
  else
    echo "${dir}/phase-review.json"
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq が未インストールです。category=ac_missing チェックをスキップします" >&2
else
  CHECKPOINT_FILE=$(_resolve_checkpoint_file)
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    AC_MISSING_COUNT=$(jq '[.findings[]? | select(.severity == "WARNING" and .category == "ac_missing")] | length' "$CHECKPOINT_FILE" 2>/dev/null || echo "0")
    AC_MISSING_COUNT="${AC_MISSING_COUNT:-0}"
    if [[ "$AC_MISSING_COUNT" =~ ^[0-9]+$ ]] && [[ "$AC_MISSING_COUNT" -gt 0 ]]; then
      echo "REJECT: phase-review findings に category=ac_missing の WARNING が ${AC_MISSING_COUNT} 件存在します。AC を達成してから merge してください" >&2
      exit 1
    fi
  fi
fi
