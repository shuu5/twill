#!/usr/bin/env bash
# experiments/EXP-015-gh-project-status-update.smoke.sh
# EXP-015: gh project item-edit で status 更新
#
# verify 対象:
#   gh project field-list で Status field id 取得 → item-edit で実 status 更新
#   server-side で Status が "Todo" → "In Progress" に変わったことを grep 検証
#
# verify_source: https://cli.github.com/manual/gh_project_item-edit

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/smoke-common.sh"

SMOKE_EXP_ID="EXP-015"
SMOKE_VERIFY_SOURCE="https://cli.github.com/manual/gh_project_item-edit"

# ── main ────────────────────────────────────────────────────────
smoke_parse_args "$@"
smoke_init_log
smoke_check_prereqs
smoke_ensure_board_env
smoke_trap_cleanup

# ── Status field option ID 取得 ─────────────────────────────────
smoke_log "Status field options 取得中..."
FIELDS_JSON=$(gh project field-list "$TWL_SMOKE_BOARD_NUM" --owner "$TWL_SMOKE_BOARD_OWNER" --format json 2>&1)
echo "$FIELDS_JSON" >> "$SMOKE_LOG_FILE"

IN_PROGRESS_OPTION_ID=$(echo "$FIELDS_JSON" | jq -r '.fields[] | select(.name=="Status") | .options[] | select(.name=="In Progress") | .id')
TODO_OPTION_ID=$(echo "$FIELDS_JSON" | jq -r '.fields[] | select(.name=="Status") | .options[] | select(.name=="Todo") | .id')

[[ -n "$IN_PROGRESS_OPTION_ID" && -n "$TODO_OPTION_ID" ]] || {
    smoke_log "error: status option id 取得失敗"
    smoke_add_check "verify" "Status options 取得" "gh project field-list" "Todo + In Progress" "missing" "fail"
    smoke_emit_result false "Status options 取得失敗"
    exit 1
}

smoke_log "Todo=$TODO_OPTION_ID, In Progress=$IN_PROGRESS_OPTION_ID"

# ── operation: gh project item-edit で status を "In Progress" に更新 ─
smoke_log "operation: status 更新 (gh CLI)..."
EDIT_RESULT=$(gh project item-edit \
    --id "$TWL_SMOKE_ISSUE_ITEM_ID" \
    --project-id "$TWL_SMOKE_BOARD_ID" \
    --field-id "$TWL_SMOKE_STATUS_FIELD_ID" \
    --single-select-option-id "$IN_PROGRESS_OPTION_ID" 2>&1) && EDIT_RC=0 || EDIT_RC=$?
echo "$EDIT_RESULT" >> "$SMOKE_LOG_FILE"

if [[ "$EDIT_RC" -eq 0 ]]; then
    smoke_add_check "gh_cli" "gh project item-edit success" \
        "gh project item-edit --field-id $TWL_SMOKE_STATUS_FIELD_ID --single-select-option-id $IN_PROGRESS_OPTION_ID" \
        "exit=0" "exit=0" "pass"
else
    smoke_add_check "gh_cli" "gh project item-edit success" \
        "gh project item-edit" "exit=0" "exit=$EDIT_RC: $EDIT_RESULT" "fail"
fi

# ── server-side state grep ──────────────────────────────────────
smoke_log "server-side state 検証..."
ITEMS_JSON=$(gh project item-list "$TWL_SMOKE_BOARD_NUM" --owner "$TWL_SMOKE_BOARD_OWNER" --format json 2>&1)
echo "$ITEMS_JSON" >> "$SMOKE_LOG_FILE"

ACTUAL_STATUS=$(echo "$ITEMS_JSON" | jq -r --arg id "$TWL_SMOKE_ISSUE_ITEM_ID" \
    '.items[] | select(.id==$id) | .status // empty')

if [[ "$ACTUAL_STATUS" == "In Progress" ]]; then
    smoke_add_check "server_state" "item.status == 'In Progress'" \
        "gh project item-list | jq '.items[] | select(.id=='\''$TWL_SMOKE_ISSUE_ITEM_ID'\'') | .status'" \
        "In Progress" "$ACTUAL_STATUS" "pass"
else
    smoke_add_check "server_state" "item.status == 'In Progress'" \
        "gh project item-list" "In Progress" "$ACTUAL_STATUS" "fail"
fi

# ── restore: Todo に戻す ────────────────────────────────────────
# Fix 9: restore 失敗を verify_checks に記録 (silent failure 防止)
smoke_log "restore: status を Todo に戻す..."
RESTORE_RC=0
gh project item-edit \
    --id "$TWL_SMOKE_ISSUE_ITEM_ID" \
    --project-id "$TWL_SMOKE_BOARD_ID" \
    --field-id "$TWL_SMOKE_STATUS_FIELD_ID" \
    --single-select-option-id "$TODO_OPTION_ID" >> "$SMOKE_LOG_FILE" 2>&1 || RESTORE_RC=$?
if [[ "$RESTORE_RC" -eq 0 ]]; then
    smoke_add_check "verify" "status restore to Todo" \
        "gh project item-edit --single-select-option-id Todo" \
        "exit=0" "exit=0" "pass"
else
    smoke_add_check "verify" "status restore to Todo" \
        "gh project item-edit --single-select-option-id Todo" \
        "exit=0" "exit=$RESTORE_RC" "fail"
fi

# ── result emit ─────────────────────────────────────────────────
if smoke_all_checks_pass; then
    smoke_emit_result true ""
else
    smoke_emit_result false "1 件以上の verify_check が fail"
    exit 1
fi
