#!/usr/bin/env bash
# resolve-issue-num.sh - CWD 非依存の Issue 番号解決
#
# resolve_issue_num() を提供する。
# 優先度 1: AUTOPILOT_DIR の state file スキャン（status=running）
# 優先度 2: git branch --show-current フォールバック
#
# 使用例:
#   source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh"
#   ISSUE_NUM=$(resolve_issue_num)

resolve_issue_num() {
  local issue_num=""
  local num f

  # Priority 1: AUTOPILOT_DIR state file scan
  if [ -n "${AUTOPILOT_DIR:-}" ] && [ -d "${AUTOPILOT_DIR}/issues" ]; then
    # パストラバーサル防止: AUTOPILOT_DIR が期待ベースパス配下であることを確認
    local canonical_dir
    canonical_dir=$(realpath -s "${AUTOPILOT_DIR}" 2>/dev/null || echo "${AUTOPILOT_DIR}")
    case "${canonical_dir}" in
      */../*|*/..)
        echo "WARNING: AUTOPILOT_DIR contains path traversal: ${AUTOPILOT_DIR}" >&2
        ;;
      *)
        issue_num=$(
          for f in "${canonical_dir}/issues/issue-"*.json; do
            [ -f "$f" ] || continue
            # jq: .status=running かつ .issue が数値型のみ選択（null 混入防止）
            num=$(jq -r 'if .status == "running" and (.issue | type == "number") then .issue | tostring else empty end' "$f" 2>/dev/null)
            if [ $? -ne 0 ]; then
              echo "WARNING: broken JSON: $f" >&2
              continue
            fi
            [ -n "$num" ] && echo "$num"
          done | sort -n | head -1
          # sort -n の最小番号採用: 複数 running 時は最も古い（小さい番号の）Issue を優先
          # Worker は通常1セッション=1 Issue のため複数 running は異常系
        )
        ;;
    esac
  fi

  # Priority 2: Fallback to git branch
  if [ -z "${issue_num:-}" ]; then
    issue_num=$(git branch --show-current 2>/dev/null \
      | grep -oP '^\w+/\K\d+(?=-)' 2>/dev/null || echo "")
  fi

  echo "${issue_num:-}"
}
