#!/usr/bin/env bash
# pr-link-issue.sh - 既存 PR の本文に Closes #N を追記する修復ヘルパー
#
# Usage:
#   bash plugins/twl/scripts/pr-link-issue.sh <issue_num> <pr_num> [--close-issue] [--repo OWNER/REPO]
#
# 機能:
#   - gh pr view で現在の PR 本文を取得
#   - Closes #${issue_num} が既に含まれていれば no-op
#   - 含まれていなければ追記して gh pr edit
#   - --close-issue 指定時は gh issue close を**直接**呼ぶ
#
# 注意: GitHub は PR merge 後の本文編集を auto-close 再評価しない。
# 既に merge 済みの PR で Issue を CLOSED にしたい場合は、--close-issue
# フラグを必ず付けること。本フラグは「auto-close を期待せず gh issue close
# を直接実行する」操作である。

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash pr-link-issue.sh <issue_num> <pr_num> [OPTIONS]

Arguments:
  issue_num      対象 Issue 番号 (例: 136)
  pr_num         対象 PR 番号 (例: 200)

Options:
  --close-issue       gh issue close を直接実行する（merge 済み PR 用）
                      注意: GitHub は merge 後の本文編集を auto-close 再評価
                      しないため、merged PR で Issue を閉じたい場合は本
                      フラグを必ず付けること。
  --repo OWNER/REPO   クロスリポ指定（省略時は CWD のリポを使用）
  -h, --help          このヘルプを表示
EOF
}

ISSUE_NUM=""
PR_NUM=""
CLOSE_ISSUE=false
REPO_FLAG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --close-issue)
      CLOSE_ISSUE=true
      shift
      ;;
    --repo)
      REPO_FLAG=(--repo "$2")
      shift 2
      ;;
    --repo=*)
      REPO_FLAG=(--repo "${1#--repo=}")
      shift
      ;;
    -*)
      echo "[pr-link-issue] Error: 不明なオプション: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$ISSUE_NUM" ]]; then
        ISSUE_NUM="$1"
      elif [[ -z "$PR_NUM" ]]; then
        PR_NUM="$1"
      else
        echo "[pr-link-issue] Error: 余分な引数: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$ISSUE_NUM" || -z "$PR_NUM" ]]; then
  echo "[pr-link-issue] Error: issue_num と pr_num が必須" >&2
  usage >&2
  exit 1
fi

if ! [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
  echo "[pr-link-issue] Error: 不正な issue_num: $ISSUE_NUM" >&2
  exit 1
fi
if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
  echo "[pr-link-issue] Error: 不正な pr_num: $PR_NUM" >&2
  exit 1
fi

# --- 現在の PR body 取得 ---
CURRENT_BODY="$(gh pr view "$PR_NUM" "${REPO_FLAG[@]}" --json body -q .body)"

# --- Closes #N 既存チェック ---
if echo "$CURRENT_BODY" | grep -Eq "(Closes|Fixes|Resolves)[[:space:]]+#${ISSUE_NUM}\b"; then
  echo "[pr-link-issue] PR #${PR_NUM} の本文に既に Closes #${ISSUE_NUM} が含まれています (no-op)"
else
  NEW_BODY="${CURRENT_BODY}

Closes #${ISSUE_NUM}"
  gh pr edit "$PR_NUM" "${REPO_FLAG[@]}" --body "$NEW_BODY"
  echo "[pr-link-issue] PR #${PR_NUM} の本文に Closes #${ISSUE_NUM} を追記しました"
fi

# --- --close-issue: gh issue close を直接実行 ---
if [[ "$CLOSE_ISSUE" == "true" ]]; then
  ISSUE_STATE="$(gh issue view "$ISSUE_NUM" "${REPO_FLAG[@]}" --json state -q .state 2>/dev/null || echo "")"
  if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
    echo "[pr-link-issue] Issue #${ISSUE_NUM} は既に CLOSED です (no-op)"
  else
    gh issue close "$ISSUE_NUM" "${REPO_FLAG[@]}"
    echo "[pr-link-issue] Issue #${ISSUE_NUM} を CLOSED にしました（gh issue close 直接実行）"
  fi
fi
