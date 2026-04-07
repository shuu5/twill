#!/usr/bin/env bash
# pr-create-helper.sh - 共通ヘルパー関数: PR 作成時に Closes #N を機械的に挿入
# 使用方法: source "${SCRIPT_DIR}/lib/pr-create-helper.sh"
#
# 提供関数:
#   pr_create_with_closes <issue_num> [label] [extra_args...]
#     - latest commit message を PR body にコピー
#     - body に Closes #${issue_num} が無ければ機械的に追記
#     - gh pr create を実行（title は latest commit subject）
#
# 背景: gh pr create --fill は commit message をそのまま PR body にコピーするが、
# commit message に Closes #N が含まれない場合 GitHub auto-close が発火しない。
# このヘルパーは PR 作成時点で確実に Closes #N を本文に含める。

pr_create_with_closes() {
  local issue_num="$1"
  shift || true

  if [[ -z "$issue_num" ]]; then
    echo "[pr-create-helper] Error: ISSUE_NUM 必須" >&2
    return 1
  fi
  if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
    echo "[pr-create-helper] Error: 不正な ISSUE_NUM: ${issue_num}" >&2
    return 1
  fi

  local label=""
  if [[ $# -gt 0 ]]; then
    label="$1"
    shift || true
  fi

  local commit_subject commit_body
  commit_subject="$(git log -1 --format=%s)"
  commit_body="$(git log -1 --format=%B)"

  local body
  if echo "$commit_body" | grep -Eq "(Closes|Fixes|Resolves)[[:space:]]+#${issue_num}\b"; then
    body="$commit_body"
  else
    body="${commit_body}

Closes #${issue_num}"
  fi

  local cmd=(gh pr create --title "$commit_subject" --body "$body")
  if [[ -n "$label" ]]; then
    cmd+=(--label "$label")
  fi
  if [[ $# -gt 0 ]]; then
    cmd+=("$@")
  fi

  "${cmd[@]}"
}
