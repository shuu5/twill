#!/usr/bin/env bash
# issue-create-refined.sh - Issue 起票 + Status=Refined 自動遷移
#
# gh issue create を呼び出した後 Project Board Status を Refined に設定する。
# Issue #1469: bug Issue 起票後 Status=Todo のまま autopilot gate で reject される問題の修正。
#
# 引数:
#   --title <title>    Issue タイトル
#   --body <body>      Issue 本文
#   --label <label>    ラベル（複数可、繰り返し）
#   --repo <owner/repo> 対象リポジトリ
#   --dry-run          実際の gh 呼び出しをスキップして終了コード 0 を返す

set -euo pipefail

TITLE=""
BODY=""
LABELS=()
REPO=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   TITLE="$2"; shift 2 ;;
    --body)    BODY="$2"; shift 2 ;;
    --label)   LABELS+=("$2"); shift 2 ;;
    --repo)    REPO="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *)         shift ;;
  esac
done

if [[ "$DRY_RUN" == "true" ]]; then
  exit 0
fi

# Issue 起票
ISSUE_ARGS=(issue create)
[[ -n "$TITLE" ]] && ISSUE_ARGS+=(--title "$TITLE")
[[ -n "$BODY" ]]  && ISSUE_ARGS+=(--body "$BODY")
for lbl in "${LABELS[@]:-}"; do
  [[ -n "${lbl:-}" ]] && ISSUE_ARGS+=(--label "$lbl")
done
[[ -n "$REPO" ]]  && ISSUE_ARGS+=(--repo "$REPO")

ISSUE_NUMBER=$(gh "${ISSUE_ARGS[@]}")

# Status=Refined に遷移
SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPTS_ROOT}/chain-runner.sh" board-status-update "$ISSUE_NUMBER" Refined
