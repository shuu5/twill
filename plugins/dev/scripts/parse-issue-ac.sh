#!/bin/bash
# parse-issue-ac.sh
# Issue body + コメントから受け入れ基準（AC）を抽出
# Usage: parse-issue-ac.sh <issue-number>
# Output: 番号付き AC リストを stdout に出力
# Exit: 0=AC抽出成功, 1=エラー, 2=ACセクションなし

set -uo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: parse-issue-ac.sh <issue-number>" >&2
    exit 1
fi

ISSUE_NUMBER="$1"

# 整数検証（引数インジェクション防止）
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "エラー: Issue番号は整数である必要があります: ${ISSUE_NUMBER}" >&2
    exit 1
fi

# Issue body 取得
ISSUE_BODY=$(gh api "repos/{owner}/{repo}/issues/${ISSUE_NUMBER}" --jq '.body' 2>/dev/null) || true
if [ -z "$ISSUE_BODY" ]; then
    echo "エラー: Issue #${ISSUE_NUMBER} の取得に失敗" >&2
    exit 1
fi

# Issue コメント取得（body とは別変数で保持）
ISSUE_COMMENTS=$(gh api "repos/{owner}/{repo}/issues/${ISSUE_NUMBER}/comments" --jq '[.[].body] | join("\n---\n")' 2>/dev/null) || true

# PR Review コメント取得（PR が存在する場合のみ）
PR_NUMBER=$(gh api "repos/{owner}/{repo}/issues/${ISSUE_NUMBER}" --jq '.pull_request.url // empty' 2>/dev/null | grep -oP '\d+$') || true
# PR番号の整数検証（APIレスポンス改ざん防止）
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    PR_NUMBER=""
fi
PR_REVIEW_COMMENTS=""
if [ -n "$PR_NUMBER" ]; then
    PR_REVIEW_COMMENTS=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/comments" --jq '[.[].body] | join("\n---\n")' 2>/dev/null) || true
    PR_REVIEWS=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews" --jq '[.[].body // empty | select(. != "")] | join("\n---\n")' 2>/dev/null) || true
    if [ -n "$PR_REVIEWS" ]; then
        if [ -n "$PR_REVIEW_COMMENTS" ]; then
            PR_REVIEW_COMMENTS="${PR_REVIEW_COMMENTS}"$'\n---\n'"${PR_REVIEWS}"
        else
            PR_REVIEW_COMMENTS="$PR_REVIEWS"
        fi
    fi
fi

# 受け入れ基準セクションを抽出
# ## 受け入れ基準 から次の ## まで、または EOF まで
AC_SECTION=$(printf '%s\n' "$ISSUE_BODY" | sed -n '/^## 受け入れ基準/,/^## [^#]/p' | sed '$d')

# セクションが空の場合（見出しだけ or 見出し自体がない）
if [ -z "$AC_SECTION" ]; then
    # EOF で終わるケース（次の ## がない）
    AC_SECTION=$(printf '%s\n' "$ISSUE_BODY" | sed -n '/^## 受け入れ基準/,$p')
fi

if [ -z "$AC_SECTION" ]; then
    echo "ACセクションなし" >&2
    exit 2
fi

# - [ ] 行を抽出し番号付きで出力
AC_LINES=$(printf '%s\n' "$AC_SECTION" | grep -E '^[[:space:]]*- \[[ x]\]' || true)

if [ -z "$AC_LINES" ]; then
    echo "ACセクションにチェックボックスなし" >&2
    exit 2
fi

# コメントからもチェックボックス形式の AC を抽出し末尾に追加
COMMENT_AC_LINES=""
if [ -n "$ISSUE_COMMENTS" ]; then
    COMMENT_AC_LINES=$(printf '%s\n' "$ISSUE_COMMENTS" | grep -E '^[[:space:]]*- \[[ x]\]' || true)
fi
if [ -n "$PR_REVIEW_COMMENTS" ]; then
    PR_AC_LINES=$(printf '%s\n' "$PR_REVIEW_COMMENTS" | grep -E '^[[:space:]]*- \[[ x]\]' || true)
    if [ -n "$PR_AC_LINES" ]; then
        if [ -n "$COMMENT_AC_LINES" ]; then
            COMMENT_AC_LINES="${COMMENT_AC_LINES}"$'\n'"${PR_AC_LINES}"
        else
            COMMENT_AC_LINES="$PR_AC_LINES"
        fi
    fi
fi

# body 由来 AC とコメント由来 AC を結合（別変数で保持した上で出力時に結合）
ALL_AC_LINES="$AC_LINES"
if [ -n "$COMMENT_AC_LINES" ]; then
    ALL_AC_LINES="${ALL_AC_LINES}"$'\n'"${COMMENT_AC_LINES}"
fi

# 番号付きで出力（チェックボックスのテキスト部分のみ）
INDEX=1
while IFS= read -r line; do
    [ -z "$line" ] && continue
    # "- [ ] " or "- [x] " プレフィックスを除去してテキスト抽出
    TEXT=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*- \[[ x]\][[:space:]]*//')
    printf '%s\n' "${INDEX}. ${TEXT}"
    INDEX=$((INDEX + 1))
done <<< "$ALL_AC_LINES"
