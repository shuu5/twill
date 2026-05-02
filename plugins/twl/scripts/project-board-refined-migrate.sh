#!/usr/bin/env bash
# project-board-refined-migrate.sh - refined label 付き Issue を Status=Refined に一括移行
#
# Usage:
#   bash scripts/project-board-refined-migrate.sh [--dry-run] [--force]
#
# Flags:
#   --dry-run  (default) Status を変更せず、対象 Issue を report のみ
#   --force    実際に Status=Refined に更新する
#
# 冪等: 既に Status=Refined の Issue はスキップ
# 0-count: 対象 Issue が 0 件でも正常終了

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 引数パーサー ──────────────────────────────────────────────
DRY_RUN=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force)   DRY_RUN=0; shift ;;
    *) echo "Error: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# ── 設定 ─────────────────────────────────────────────────────
PROJECT_NUM=6
OWNER="shuu5"
REPO="shuu5/twill"
# Status field ID (PVTSSF_lAHOCNFEd84BTu2WzhA7yTs) と Refined option ID (3d983780)
STATUS_FIELD_ID="PVTSSF_lAHOCNFEd84BTu2WzhA7yTs"
REFINED_OPTION_ID="3d983780"

echo "=== project-board-refined-migrate.sh ==="
echo "Mode: $([ "$DRY_RUN" -eq 1 ] && echo 'dry-run' || echo 'force')"
echo ""

# ── Step 1: Refined option ID の存在確認 ──────────────────────
echo "Step 1: Status field の Refined option ID 確認..."
FIELDS=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json 2>/dev/null || echo "")
if [[ -z "$FIELDS" ]]; then
  echo "⚠️  project field-list 取得失敗 (gh auth refresh -s project が必要な場合あり)"
  exit 0
fi

FOUND_REFINED=$(echo "$FIELDS" | jq -r --arg rid "$REFINED_OPTION_ID" \
  '.fields[] | select(.name=="Status") | .options[]? | select(.id==$rid) | .id' 2>/dev/null || echo "")
if [[ -n "$FOUND_REFINED" ]]; then
  echo "✓ Refined option ID (3d983780) 確認済み"
else
  echo "⚠️  Refined option ID (3d983780) が Status field に見つかりません"
  echo "   gh project field-list $PROJECT_NUM --owner $OWNER で確認してください"
  exit 0
fi
echo ""

# ── Step 2: refined ラベル付き OPEN Issue を取得 ──────────────
echo "Step 2: refined ラベル付き OPEN Issue を取得..."
LABELED_ISSUES=$(gh issue list --label "refined" --repo "$REPO" --state open \
  --json number,title 2>/dev/null || echo "[]")
ISSUE_COUNT=$(echo "$LABELED_ISSUES" | jq 'length')

if [[ "$ISSUE_COUNT" -eq 0 ]]; then
  echo "ℹ️  migration scope = 0 件（refined ラベル付き OPEN Issue なし）"
  echo "✓ 正常終了"
  exit 0
fi

echo "対象 Issue: ${ISSUE_COUNT} 件"
echo "$LABELED_ISSUES" | jq -r '.[] | "  #\(.number) \(.title)"'
echo ""

# ── Step 3: Board アイテム取得 ────────────────────────────────
echo "Step 3: Project Board アイテム取得..."
BOARD_ITEMS=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" \
  --format json --limit 200 2>/dev/null || echo "")
if [[ -z "$BOARD_ITEMS" ]]; then
  echo "⚠️  Board アイテム取得失敗"
  exit 0
fi

PROJECT_ID=$(gh api graphql -f query='
  query($owner: String!, $num: Int!) {
    user(login: $owner) { projectV2(number: $num) { id } }
  }' -f owner="$OWNER" -F num="$PROJECT_NUM" \
  -q '.data.user.projectV2.id' 2>/dev/null || echo "")

# ── set_status_refined: Status=Refined への単体設定 helper ──────
# explore section 7.1 set_status_refined() を migration script に正式組み込み
set_status_refined() {
  local item_id="$1"
  local project_id="$2"
  gh project item-edit \
    --id "$item_id" \
    --project-id "$project_id" \
    --field-id "$STATUS_FIELD_ID" \
    --single-select-option-id "$REFINED_OPTION_ID" >/dev/null 2>&1
}

# ── Step 4: 各 Issue を処理 ───────────────────────────────────
echo "Step 4: Status 更新処理..."
UPDATED=0
SKIPPED=0
NOT_ON_BOARD=0

while IFS= read -r issue_num; do
  current_status=$(echo "$BOARD_ITEMS" | jq -r --argjson n "$issue_num" \
    '.items[] | select(.content.number==$n and .content.type=="Issue") | .status // empty' \
    2>/dev/null | head -1)

  if [[ "$current_status" == "Refined" ]]; then
    echo "  #${issue_num}: 既に Status=Refined → スキップ（冪等）"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # In Progress / Done は active 状態 → 上書き禁止
  if [[ "$current_status" == "In Progress" || "$current_status" == "Done" ]]; then
    echo "  #${issue_num}: Status=${current_status} → アクティブ状態のためスキップ"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [[ -z "$current_status" ]]; then
    echo "  #${issue_num}: Board 未登録 → スキップ（手動 Board 追加が必要）"
    NOT_ON_BOARD=$((NOT_ON_BOARD + 1))
    continue
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  #${issue_num}: [dry-run] Status=${current_status} → Refined に更新予定"
  else
    ITEM_ID=$(echo "$BOARD_ITEMS" | jq -r --argjson n "$issue_num" \
      '.items[] | select(.content.number==$n and .content.type=="Issue") | .id' 2>/dev/null | head -1)
    if [[ -n "$ITEM_ID" && -n "$PROJECT_ID" ]]; then
      set_status_refined "$ITEM_ID" "$PROJECT_ID"
      echo "  #${issue_num}: Status=${current_status} → Refined ✓"
      UPDATED=$((UPDATED + 1))
    else
      echo "  #${issue_num}: item-edit 失敗 (ITEM_ID='${ITEM_ID}', PROJECT_ID='${PROJECT_ID}')"
    fi
  fi
done < <(echo "$LABELED_ISSUES" | jq -r '.[].number')

echo ""
echo "=== 完了 ==="
echo "  更新: ${UPDATED} 件 / スキップ(冪等): ${SKIPPED} 件 / Board未登録: ${NOT_ON_BOARD} 件"
[ "$DRY_RUN" -eq 1 ] && echo "  (dry-run モード: 実際の変更なし。--force で実行)"
exit 0
