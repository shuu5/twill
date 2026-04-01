#!/usr/bin/env bash
# project-board-backfill.sh - 欠落 Issue を Project Board に一括追加
#
# Usage: bash scripts/project-board-backfill.sh <start> <end>
#   start: 開始 Issue 番号
#   end:   終了 Issue 番号
#
# Example: bash scripts/project-board-backfill.sh 41 58

set -euo pipefail

# ── 引数バリデーション ──────────────────────────────────────
START="${1:-}"
END="${2:-}"

if [[ -z "$START" || -z "$END" ]]; then
  echo "Usage: bash scripts/project-board-backfill.sh <start> <end>"
  echo "Example: bash scripts/project-board-backfill.sh 41 58"
  exit 1
fi

if [[ ! "$START" =~ ^[1-9][0-9]*$ ]] || [[ ! "$END" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: start and end must be positive integers"
  exit 1
fi

if (( START > END )); then
  echo "Error: start ($START) must be <= end ($END)"
  exit 1
fi

# ── Step 0: project スコープ確認 ──────────────────────────────
if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
  echo "⚠️ gh トークンに project スコープがありません"
  echo "以下を実行してスコープを追加してください:"
  echo "  gh auth refresh -s project"
  exit 0
fi

# ── Step 1: Project 検出（TITLE_MATCH_PROJECT パターン） ──────
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"

# Project 一覧を取得
PROJECT_NUMBERS=$(gh project list --owner "$OWNER" --format json | jq -r '.projects[].number')

GRAPHQL_QUERY='
  query($owner: String!, $num: Int!) {
    user(login: $owner) {
      projectV2(number: $num) {
        id
        title
        repositories(first: 20) { nodes { nameWithOwner } }
      }
    }
  }
'
GRAPHQL_QUERY_ORG='
  query($owner: String!, $num: Int!) {
    organization(login: $owner) {
      projectV2(number: $num) {
        id
        title
        repositories(first: 20) { nodes { nameWithOwner } }
      }
    }
  }
'

MATCHED_PROJECTS=()
TITLE_MATCH_PROJECT=""

for PROJECT_NUM in $PROJECT_NUMBERS; do
  # まず user() で試行
  RESULT=$(gh api graphql -f query="$GRAPHQL_QUERY" -f owner="$OWNER" -F num="$PROJECT_NUM" 2>/dev/null) || continue
  PROJECT_DATA=$(echo "$RESULT" | jq -r '.data.user.projectV2 // empty')

  # user() が null なら organization() にフォールバック
  if [ -z "$PROJECT_DATA" ]; then
    RESULT=$(gh api graphql -f query="$GRAPHQL_QUERY_ORG" -f owner="$OWNER" -F num="$PROJECT_NUM" 2>/dev/null) || continue
    PROJECT_DATA=$(echo "$RESULT" | jq -r '.data.organization.projectV2 // empty')
  fi

  if [ -z "$PROJECT_DATA" ]; then
    continue
  fi

  # Note: repositories(first: 20) — 20件を超えるリンクがある場合は truncate される
  LINKED=$(echo "$PROJECT_DATA" | jq -r '.repositories.nodes[].nameWithOwner')
  PROJECT_TITLE=$(echo "$PROJECT_DATA" | jq -r '.title // empty')

  if echo "$LINKED" | grep -qxF "$REPO"; then
    PROJECT_ID=$(echo "$PROJECT_DATA" | jq -r '.id')
    MATCHED_PROJECTS+=("$PROJECT_NUM:$PROJECT_ID")

    if [[ "$PROJECT_TITLE" == *"$REPO_NAME"* ]] && [ -z "$TITLE_MATCH_PROJECT" ]; then
      TITLE_MATCH_PROJECT="$PROJECT_NUM:$PROJECT_ID"
    fi
  fi
done

# 優先選択
if [ -n "$TITLE_MATCH_PROJECT" ]; then
  PROJECT_NUM="${TITLE_MATCH_PROJECT%%:*}"
  PROJECT_ID="${TITLE_MATCH_PROJECT#*:}"
elif [ ${#MATCHED_PROJECTS[@]} -gt 0 ]; then
  if [ ${#MATCHED_PROJECTS[@]} -gt 1 ]; then
    echo "⚠️ 複数の Project が検出されました。最初の Project を使用します。"
  fi
  PROJECT_NUM="${MATCHED_PROJECTS[0]%%:*}"
  PROJECT_ID="${MATCHED_PROJECTS[0]#*:}"
else
  echo "ℹ️ リポジトリにリンクされた Project がありません。スキップします。"
  exit 0
fi

echo "Project: #$PROJECT_NUM ($PROJECT_ID)"

# ── Step 2: Status フィールド情報取得（ループ外で1回） ─────────
STATUS_FIELD_ID=""
IN_PROGRESS_OPTION_ID=""

FIELDS_JSON=$(gh api graphql -f query='
query($nodeId: ID!) {
  node(id: $nodeId) {
    ... on ProjectV2 {
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options { id name }
          }
        }
      }
    }
  }
}' -f nodeId="$PROJECT_ID" --jq '.data.node.fields.nodes[] | select(.name == "Status")' 2>/dev/null) || true

if [ -n "$FIELDS_JSON" ]; then
  STATUS_FIELD_ID=$(echo "$FIELDS_JSON" | jq -r '.id')
  IN_PROGRESS_OPTION_ID=$(echo "$FIELDS_JSON" | jq -r '.options[] | select(.name == "In Progress") | .id')
else
  echo "⚠️ Status フィールドを取得できませんでした。Status 設定はスキップされます。"
fi

# ── Step 3: Issue ループ ───────────────────────────────────────
echo ""
echo "## Project Board バックフィル結果"
echo ""
echo "| Issue | 追加 | Status | 備考 |"
echo "|-------|------|--------|------|"

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

for (( i=START; i<=END; i++ )); do
  # Issue 存在チェック
  if ! gh issue view "$i" --repo "$REPO" --json number >/dev/null 2>&1; then
    echo "| #$i | - | - | ⚠️ Issue が存在しない |"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    sleep 1
    continue
  fi

  # Project に追加
  ITEM_RESULT=$(gh project item-add "$PROJECT_NUM" --owner "$OWNER" \
    --url "https://github.com/$REPO/issues/$i" --format json 2>&1) || {
    echo "| #$i | ❌ | - | API エラー |"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    sleep 1
    continue
  }

  ITEM_ID=$(echo "$ITEM_RESULT" | jq -r '.id // empty')

  # Status を In Progress に設定
  STATUS_MSG="-"
  if [ -n "$STATUS_FIELD_ID" ] && [ -n "$IN_PROGRESS_OPTION_ID" ] && [ -n "$ITEM_ID" ]; then
    if gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
      --field-id "$STATUS_FIELD_ID" --single-select-option-id "$IN_PROGRESS_OPTION_ID" >/dev/null 2>&1; then
      STATUS_MSG="In Progress"
    else
      STATUS_MSG="⚠️ 設定失敗"
    fi
  fi

  echo "| #$i | ✓ | $STATUS_MSG | |"
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

  # API レート制限対策
  sleep 1
done

echo ""
echo "---"
echo "合計: 成功=$SUCCESS_COUNT スキップ=$SKIP_COUNT 失敗=$FAIL_COUNT"
echo ""
echo "検証コマンド:"
echo "  gh project item-list --owner @me $PROJECT_NUM --format json | jq '[.items[].content.number] | sort'"
