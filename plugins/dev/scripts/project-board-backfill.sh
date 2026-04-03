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

# ── Step 1: Project 検出 ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/resolve-project.sh
source "${SCRIPT_DIR}/lib/resolve-project.sh"

if ! read -r PROJECT_NUM PROJECT_ID OWNER _REPO_NAME REPO < <(resolve_project 2>/dev/null); then
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
echo "  gh project item-list $PROJECT_NUM --owner $OWNER --format json | jq '[.items[].content.number] | sort'"
