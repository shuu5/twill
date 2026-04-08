#!/usr/bin/env bash
# ac-checklist-gen.sh — Issue body の AC を checkbox 化し副作用キーワードを [!] でマーク
#
# Usage: ac-checklist-gen.sh <issue-number>
# Output: stdout（Pilot がコピペ or リダイレクトで利用）
set -euo pipefail

ISSUE_NUM="${1:?Issue number required}"

BODY=$(gh issue view "$ISSUE_NUM" --json body -q .body)

# 副作用キーワードパターン（日本語・英語両対応、部分一致）
SIDE_EFFECT_PATTERN='Issue にコメント|gh issue comment|comment.*[Ii]ssue|gh label|ラベル追加|--add-label|README|ドキュメント更新|docs?/|architecture/'

echo "# AC Checklist for Issue #$ISSUE_NUM"
echo ""

# `## 受け入れ基準` セクション抽出
AC_LINES=$(awk '/^## 受け入れ基準/{found=1; next} found && /^## /{found=0} found && /^- \[/{print}' <<< "$BODY")

if [[ -z "$AC_LINES" ]]; then
  echo "ERROR: '## 受け入れ基準' セクションが見つかりません (Issue #$ISSUE_NUM)" >&2
  exit 1
fi

while IFS= read -r line; do
  if echo "$line" | grep -qE "$SIDE_EFFECT_PATTERN"; then
    echo "[!] ${line} — PR 外副作用あり — 完了時 verify 必須"
  else
    echo "$line"
  fi
done <<< "$AC_LINES"
