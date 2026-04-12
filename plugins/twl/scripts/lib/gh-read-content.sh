#!/usr/bin/env bash
# gh-read-content.sh — Issue/PR body + comments の全文取得ヘルパー
#
# ポリシー: content-reading（内容理解を目的とする読み込み）は body + comments 必須。
# meta-only（state/labels/number/id 等の属性取得）は対象外。
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/gh-read-content.sh"
#   content=$(gh_read_issue_full 499 --repo shuu5/twill)
#   content=$(gh_read_pr_full 392 --repo shuu5/twill)

# gh_read_issue_full <issue-number> [--repo <owner/repo>]
# Issue の body と全 comments を結合した単一テキストを標準出力する。
# 切り詰めなし。エラー時は空文字列 + stderr 警告。
gh_read_issue_full() {
  local issue="$1"; shift
  local repo_flag=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_flag=(--repo "$2"); shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$issue" ]]; then
    echo "WARN: gh_read_issue_full: issue 番号が未指定" >&2
    return 0
  fi

  local body comments
  body=$(gh issue view "$issue" "${repo_flag[@]}" --json body -q '.body' 2>/dev/null || echo "")
  comments=$(gh issue view "$issue" "${repo_flag[@]}" --json comments -q '[.comments[].body] | join("\n\n---\n\n")' 2>/dev/null || echo "")

  if [[ -z "$body" && -z "$comments" ]]; then
    echo "WARN: gh_read_issue_full: Issue #${issue} の body/comments 取得失敗" >&2
    return 0
  fi

  printf '%s\n\n## === Comments ===\n\n%s\n' "$body" "$comments"
}

# gh_read_pr_full <pr-number> [--repo <owner/repo>]
# PR の body と全 comments を結合した単一テキストを標準出力する。
# 切り詰めなし。エラー時は空文字列 + stderr 警告。
gh_read_pr_full() {
  local pr="$1"; shift
  local repo_flag=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_flag=(--repo "$2"); shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$pr" ]]; then
    echo "WARN: gh_read_pr_full: PR 番号が未指定" >&2
    return 0
  fi

  local body comments
  body=$(gh pr view "$pr" "${repo_flag[@]}" --json body -q '.body' 2>/dev/null || echo "")
  comments=$(gh pr view "$pr" "${repo_flag[@]}" --json comments -q '[.comments[].body] | join("\n\n---\n\n")' 2>/dev/null || echo "")

  if [[ -z "$body" && -z "$comments" ]]; then
    echo "WARN: gh_read_pr_full: PR #${pr} の body/comments 取得失敗" >&2
    return 0
  fi

  printf '%s\n\n## === Comments ===\n\n%s\n' "$body" "$comments"
}
