#!/usr/bin/env bash
# project-board-archive.sh - Project Board の Done アイテムを一括アーカイブ
#
# Usage: bash scripts/project-board-archive.sh [--dry-run] [--no-verify]
#   --dry-run:   実際のアーカイブなしに対象一覧を表示
#   --no-verify: GitHub Issue state 二重チェックをスキップ（従来挙動）
#
# デフォルトは fail-closed: Project Board status=Done かつ
# GitHub Issue state=CLOSED の両方を満たす場合のみ archive する（Issue #138）
#
# Example:
#   bash scripts/project-board-archive.sh --dry-run
#   bash scripts/project-board-archive.sh
#   bash scripts/project-board-archive.sh --no-verify  # 従来挙動

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/python-env.sh
source "${SCRIPT_DIR}/lib/python-env.sh"

# ── 引数解析 ───────────────────────────────────────────────────
DRY_RUN=false
NO_VERIFY=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --no-verify) NO_VERIFY=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# ── Step 0: project スコープ確認 ──────────────────────────────
if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
  GH_SCOPE_TEST=$(gh auth status 2>&1 || true)
  if echo "$GH_SCOPE_TEST" | grep -qi "project"; then
    echo "⚠️ gh トークンに project スコープがありません"
    echo "以下を実行してスコープを追加してください:"
    echo "  gh auth refresh -s project"
  else
    echo "⚠️ gh project list に失敗しました（ネットワーク障害または認証エラーの可能性）"
  fi
  exit 0
fi

# ── Step 1: Project 検出 ──────────────────────────────────────
_RESOLVE_JSON=$(python3 -m twl.autopilot.github resolve-project 2>/dev/null) || _RESOLVE_JSON=""
if [[ -z "$_RESOLVE_JSON" ]]; then
  echo "ℹ️ リポジトリにリンクされた Project がありません。スキップします。"
  exit 0
fi
PROJECT_NUM=$(echo "$_RESOLVE_JSON" | jq -r '.project_num')
OWNER=$(echo "$_RESOLVE_JSON" | jq -r '.owner')

# ── Step 2: Done アイテム取得 ─────────────────────────────────
ITEMS_JSON=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json --limit 200)
if [[ -z "$ITEMS_JSON" ]]; then
  echo "⚠️ gh project item-list の取得に失敗しました"
  exit 1
fi

DONE_ITEMS=$(echo "$ITEMS_JSON" | jq -c '[.items[] | select(.status == "Done")]')
DONE_COUNT=$(echo "$DONE_ITEMS" | jq 'length')

if [[ "$DONE_COUNT" -eq 0 ]]; then
  echo "Done アイテムはありません"
  exit 0
fi

# ── Step 3: dry-run / 通常実行 ────────────────────────────────
if $DRY_RUN; then
  echo "[dry-run] アーカイブ対象一覧:"
  echo "$DONE_ITEMS" | jq -r '.[] | "  #" + (.content.number | tostring) + " " + (.title // .content.title // "(タイトルなし)")'
  echo ""
  echo "[dry-run] ${DONE_COUNT} 件をアーカイブ対象として検出"
  exit 0
fi

ARCHIVED_COUNT=0
SKIPPED_COUNT=0
while IFS= read -r ITEM; do
  ITEM_ID=$(echo "$ITEM" | jq -r '.id')
  ISSUE_NUM=$(echo "$ITEM" | jq -r '.content.number // "N/A"')

  # NEW: GitHub Issue state 二重チェック (fail-closed, Issue #138)
  # --no-verify 時はスキップ（従来挙動）
  if ! $NO_VERIFY && [[ "$ISSUE_NUM" != "N/A" ]]; then
    GH_STATE=$(gh issue view "$ISSUE_NUM" --json state -q .state 2>/dev/null || echo "")
    if [[ "$GH_STATE" != "CLOSED" ]]; then
      if [[ -z "$GH_STATE" ]]; then
        echo "  ⚠️ #${ISSUE_NUM}: GitHub state 取得失敗 — fail-closed で archive をスキップ"
      else
        echo "  ⚠️ #${ISSUE_NUM}: GitHub state=${GH_STATE} — archive をスキップ"
      fi
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      sleep 0.5
      continue
    fi
  fi

  if gh project item-archive "$PROJECT_NUM" --owner "$OWNER" --id "$ITEM_ID" >/dev/null 2>&1; then
    ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
    echo "  archived: #${ISSUE_NUM}"
  else
    echo "  ⚠️ アーカイブ失敗: #${ISSUE_NUM} (スキップ)"
  fi

  sleep 0.5
done < <(echo "$DONE_ITEMS" | jq -c '.[]')

echo ""
echo "✓ ${ARCHIVED_COUNT} 件をアーカイブしました"
if [[ "$SKIPPED_COUNT" -gt 0 ]]; then
  echo "⚠️ ${SKIPPED_COUNT} 件を fail-closed により skip しました（GitHub state が CLOSED でない）"
fi
