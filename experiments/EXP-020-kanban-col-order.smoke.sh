#!/usr/bin/env bash
# experiments/EXP-020-kanban-col-order.smoke.sh
# EXP-020: kanban col order 変更 (2 手段)
#
# verify 対象:
#   board kanban view の column 順序を変更する API 可否を検証
#   手段 (a) gh CLI: gh project view-edit (存在未確認、try & record)
#   手段 (b) GraphQL: updateProjectV2View mutation (sortBy or singleSelectFieldOptionPositions)
#
# 期待結果:
#   GitHub Projects v2 の kanban col 順序は status field の option 順序で決まる
#   updateProjectV2Field の options array 順序が UI 反映されるか検証
#
# 注: API でカラム順序を完全制御できない場合は "API_LIMITATION" として skip 記録

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/smoke-common.sh"

SMOKE_EXP_ID="EXP-020"
SMOKE_VERIFY_SOURCE="https://docs.github.com/en/graphql/reference/mutations"

# ── main ────────────────────────────────────────────────────────
smoke_parse_args "$@"
smoke_init_log
smoke_check_prereqs
smoke_ensure_board_env
smoke_trap_cleanup

# ── 既存 options 順序を取得 ─────────────────────────────────────
smoke_log "既存 options 順序を取得..."
BEFORE_OPTIONS=$(gh project field-list "$TWL_SMOKE_BOARD_NUM" --owner "$TWL_SMOKE_BOARD_OWNER" --format json \
    | jq '[.fields[] | select(.name=="Status") | .options[] | {name, id}]')
echo "before order: $BEFORE_OPTIONS" >> "$SMOKE_LOG_FILE"

BEFORE_NAMES=$(echo "$BEFORE_OPTIONS" | jq -r '[.[].name] | join(",")')
smoke_log "before order: $BEFORE_NAMES"

# 順序を reverse して update する (一意な変更を検証可能に)
REVERSED_OPTIONS=$(echo "$BEFORE_OPTIONS" \
    | jq '[reverse[] | {name, color: "GRAY", description: ""}]')

# ── 手段 (a) gh CLI: 公式に col order 変更 sub-command がないことを記録 ─
attempt_gh_cli() {
    smoke_log "attempt gh CLI: gh project sub-commands 確認..."
    # gh CLI v2 は col order 直接編集 sub-command を持たない (verified by absence)
    local cli_help
    cli_help=$(gh project --help 2>&1 || true)
    echo "$cli_help" >> "$SMOKE_LOG_FILE"

    if echo "$cli_help" | grep -qiE "view-edit|reorder|col-order"; then
        smoke_add_check "gh_cli" "gh project view-edit or reorder sub-command 存在" \
            "gh project --help" "view-edit / reorder" "found in help" "pass"
        return 0
    else
        smoke_add_check "gh_cli" "gh project view-edit or reorder sub-command 存在" \
            "gh project --help" "view-edit / reorder" "not found (gh CLI 未対応)" "fail"
        return 1
    fi
}

# ── 手段 (b) GraphQL: updateProjectV2Field で options 順序変更 ─
# 注: array variable は -f で渡せない、inline mutation 構築
attempt_graphql() {
    smoke_log "attempt GraphQL: updateProjectV2Field で options 順序 reverse..."
    # reverse 順で inline 構築
    # Fix 7: jq @json で option name 内の " / \ を escape
    local options_inline
    options_inline=$(echo "$BEFORE_OPTIONS" \
        | jq -r 'reverse | map("{name: \(.name | @json), color: GRAY, description: \"\"}") | join(", ")')

    local mutation
    mutation="mutation { updateProjectV2Field(input: { fieldId: \"$TWL_SMOKE_STATUS_FIELD_ID\", singleSelectOptions: [$options_inline] }) { projectV2Field { ... on ProjectV2SingleSelectField { options { id name } } } } }"

    local result rc
    result=$(gh api graphql -f query="$mutation" 2>&1) && rc=0 || rc=$?
    echo "graphql result: $result" >> "$SMOKE_LOG_FILE"

    if [[ "$rc" -eq 0 ]] && echo "$result" | jq -e '.data.updateProjectV2Field.projectV2Field.options' >/dev/null 2>&1; then
        smoke_add_check "graphql" "updateProjectV2Field で options 順序変更" \
            "gh api graphql inline mutation updateProjectV2Field with reversed options" \
            "exit=0 + options array returned" "${result:0:200}" "pass"
        return 0
    else
        smoke_add_check "graphql" "updateProjectV2Field で options 順序変更" \
            "gh api graphql updateProjectV2Field" \
            "exit=0" "exit=$rc: ${result:0:200}" "fail"
        return 1
    fi
}

try_methods attempt_gh_cli attempt_graphql || true

# ── server-side state grep ──────────────────────────────────────
smoke_log "server-side state 検証..."
AFTER_OPTIONS=$(gh project field-list "$TWL_SMOKE_BOARD_NUM" --owner "$TWL_SMOKE_BOARD_OWNER" --format json \
    | jq '[.fields[] | select(.name=="Status") | .options[] | {name, id}]')
echo "after order: $AFTER_OPTIONS" >> "$SMOKE_LOG_FILE"

AFTER_NAMES=$(echo "$AFTER_OPTIONS" | jq -r '[.[].name] | join(",")')
smoke_log "after order: $AFTER_NAMES"

# 順序が reverse されたか検証 (= 順序変更 API が動いた証拠)
EXPECTED_REVERSE=$(echo "$BEFORE_OPTIONS" | jq -r '[reverse[].name] | join(",")')

if [[ "$AFTER_NAMES" == "$EXPECTED_REVERSE" ]]; then
    smoke_add_check "server_state" "options 順序が reverse された" \
        "gh project field-list | jq '.fields[] | select(.name==\"Status\") | [.options[].name] | join(\",\")'" \
        "$EXPECTED_REVERSE" "$AFTER_NAMES" "pass"
elif [[ "$AFTER_NAMES" != "$BEFORE_NAMES" ]]; then
    # 順序が変わったが完全 reverse ではない (部分変更)
    smoke_add_check "server_state" "options 順序が変更された (完全 reverse でない)" \
        "gh project field-list" "$EXPECTED_REVERSE" "$AFTER_NAMES" "pass"
else
    smoke_add_check "server_state" "options 順序変更" \
        "gh project field-list" "$EXPECTED_REVERSE" "$AFTER_NAMES (変更なし)" "fail"
fi

# ── result emit ─────────────────────────────────────────────────
if smoke_method_and_server_pass; then
    smoke_emit_result true ""
else
    smoke_emit_result false "method or server_state check fail"
    exit 1
fi
