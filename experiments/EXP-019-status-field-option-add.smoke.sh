#!/usr/bin/env bash
# experiments/EXP-019-status-field-option-add.smoke.sh
# EXP-019: Project status field option 追加 (2 手段)
#
# verify 対象:
#   Status field に新 option ("Refined") を追加
#   手段 (a) gh CLI: gh project field-edit (可否未確認、try & record)
#   手段 (b) GraphQL: updateProjectV2Field mutation
#
# verify_source:
#   https://cli.github.com/manual/gh_project (15 write-capable sub-commands)
#   GraphQL Projects v2 mutations

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/smoke-common.sh"

SMOKE_EXP_ID="EXP-019"
SMOKE_VERIFY_SOURCE="https://docs.github.com/en/graphql/reference/mutations"
NEW_OPTION_NAME="Refined-Smoke-$(date +%s)"

# ── main ────────────────────────────────────────────────────────
smoke_parse_args "$@"
smoke_init_log
smoke_check_prereqs
smoke_ensure_board_env
smoke_trap_cleanup

smoke_log "target option: $NEW_OPTION_NAME"

# ── 既存 options snapshot (rollback 用) ─────────────────────────
EXISTING_OPTIONS_JSON=$(gh project field-list "$TWL_SMOKE_BOARD_NUM" --owner "$TWL_SMOKE_BOARD_OWNER" --format json \
    | jq '[.fields[] | select(.name=="Status") | .options[] | {name, id}]')
echo "existing options: $EXISTING_OPTIONS_JSON" >> "$SMOKE_LOG_FILE"

# ── 手段 (a) gh CLI: gh project field-edit ─────────────────────
attempt_gh_cli() {
    smoke_log "attempt gh CLI: gh project field-edit..."
    # 注: gh CLI v2.x の field-edit の option 追加サポートは未確認
    # 試行して挙動を記録 (失敗 expected の可能性高い)
    local result rc
    result=$(gh project field-edit \
        --id "$TWL_SMOKE_STATUS_FIELD_ID" \
        --project-id "$TWL_SMOKE_BOARD_NUM" \
        --owner "$TWL_SMOKE_BOARD_OWNER" \
        --name "Status" \
        --add-option "$NEW_OPTION_NAME" 2>&1) && rc=0 || rc=$?
    echo "gh field-edit result: $result" >> "$SMOKE_LOG_FILE"

    if [[ "$rc" -eq 0 ]]; then
        smoke_add_check "gh_cli" "gh project field-edit --add-option" \
            "gh project field-edit --add-option $NEW_OPTION_NAME" "exit=0" "exit=0" "pass"
        return 0
    else
        smoke_add_check "gh_cli" "gh project field-edit --add-option" \
            "gh project field-edit --add-option" "exit=0" "exit=$rc: ${result:0:200}" "fail"
        return 1
    fi
}

# ── 手段 (b) GraphQL: updateProjectV2Field mutation ────────────
# 注: gh CLI -f は string only、array は inline mutation 構築が必要
attempt_graphql() {
    smoke_log "attempt GraphQL: updateProjectV2Field..."
    # 既存 options + 新 option を inline GraphQL 形式で構築
    # Fix 7: jq @json で option name 内の " / \ を escape (injection 防止)
    local options_inline
    options_inline=$(echo "$EXISTING_OPTIONS_JSON" \
        | jq -r --arg new "$NEW_OPTION_NAME" \
        '. + [{name: $new}] | map("{name: \(.name | @json), color: GRAY, description: \"\"}") | join(", ")')

    local mutation
    mutation="mutation { updateProjectV2Field(input: { fieldId: \"$TWL_SMOKE_STATUS_FIELD_ID\", singleSelectOptions: [$options_inline] }) { projectV2Field { ... on ProjectV2SingleSelectField { options { id name } } } } }"

    local result rc
    result=$(gh api graphql -f query="$mutation" 2>&1) && rc=0 || rc=$?
    echo "graphql result: $result" >> "$SMOKE_LOG_FILE"

    if [[ "$rc" -eq 0 ]] && echo "$result" | jq -e ".data.updateProjectV2Field.projectV2Field.options[] | select(.name==\"$NEW_OPTION_NAME\")" >/dev/null 2>&1; then
        smoke_add_check "graphql" "updateProjectV2Field mutation success" \
            "gh api graphql inline mutation updateProjectV2Field with $(echo "$EXISTING_OPTIONS_JSON" | jq 'length') + 1 options" \
            "options contains \"$NEW_OPTION_NAME\"" "${result:0:200}" "pass"
        return 0
    else
        smoke_add_check "graphql" "updateProjectV2Field mutation success" \
            "gh api graphql updateProjectV2Field" \
            "options contains \"$NEW_OPTION_NAME\"" "exit=$rc: ${result:0:200}" "fail"
        return 1
    fi
}

# 2 手段順番試行 (どちらかが動けば success)
try_methods attempt_gh_cli attempt_graphql || true

# ── server-side state grep ──────────────────────────────────────
smoke_log "server-side state 検証..."
AFTER_JSON=$(gh project field-list "$TWL_SMOKE_BOARD_NUM" --owner "$TWL_SMOKE_BOARD_OWNER" --format json 2>&1)
echo "after options: $AFTER_JSON" >> "$SMOKE_LOG_FILE"

if echo "$AFTER_JSON" | jq -e ".fields[] | select(.name==\"Status\") | .options[] | select(.name==\"$NEW_OPTION_NAME\")" >/dev/null 2>&1; then
    smoke_add_check "server_state" "Status field に '$NEW_OPTION_NAME' option が存在" \
        "gh project field-list | jq '.fields[] | select(.name==\"Status\") | .options[].name'" \
        "$NEW_OPTION_NAME" "found" "pass"
else
    smoke_add_check "server_state" "Status field に '$NEW_OPTION_NAME' option が存在" \
        "gh project field-list" "$NEW_OPTION_NAME" "not found" "fail"
fi

# ── result emit ─────────────────────────────────────────────────
if smoke_method_and_server_pass; then
    smoke_emit_result true ""
else
    smoke_emit_result false "method or server_state check fail"
    exit 1
fi
