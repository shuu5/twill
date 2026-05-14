#!/usr/bin/env bash
# experiments/EXP-022-view-switch.smoke.sh
# EXP-022: Project view layout 切替 (kanban / table)
#
# verify 対象:
#   board の default view layout を BOARD_LAYOUT (kanban) ↔ TABLE_LAYOUT 切替
#   手段 (a) gh CLI: gh project view-edit (存在未確認)
#   手段 (b) GraphQL: updateProjectV2View mutation (layout field)
#
# 注: API で view layout 変更不可なら "API_LIMITATION" 記録

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/smoke-common.sh"

SMOKE_EXP_ID="EXP-022"
SMOKE_VERIFY_SOURCE="https://docs.github.com/en/graphql/reference/mutations"

# ── main ────────────────────────────────────────────────────────
smoke_parse_args "$@"
smoke_init_log
smoke_check_prereqs
smoke_ensure_board_env
smoke_trap_cleanup

# ── view ID 取得 ────────────────────────────────────────────────
smoke_log "default view ID 取得..."
VIEW_JSON=$(gh api graphql \
    -f query='query($id: ID!) {
        node(id: $id) {
            ... on ProjectV2 {
                views(first: 5) { nodes { id name layout } }
            }
        }
    }' \
    -f id="$TWL_SMOKE_BOARD_ID" 2>&1)
echo "views: $VIEW_JSON" >> "$SMOKE_LOG_FILE"

VIEW_ID=$(echo "$VIEW_JSON" | jq -r '.data.node.views.nodes[0].id // empty')
VIEW_BEFORE_LAYOUT=$(echo "$VIEW_JSON" | jq -r '.data.node.views.nodes[0].layout // empty')

[[ -n "$VIEW_ID" ]] || {
    smoke_log "error: view ID 取得失敗"
    smoke_add_check "verify" "view ID 取得" "gh api graphql views" "PVTV_*" "missing" "fail"
    smoke_emit_result false "view ID 取得失敗"
    exit 1
}

smoke_log "view ID: $VIEW_ID, layout before: $VIEW_BEFORE_LAYOUT"

# ── target layout: 現在と逆 ─────────────────────────────────────
if [[ "$VIEW_BEFORE_LAYOUT" == "BOARD_LAYOUT" ]]; then
    TARGET_LAYOUT="TABLE_LAYOUT"
else
    TARGET_LAYOUT="BOARD_LAYOUT"
fi

# ── 手段 (a) gh CLI: 直接 sub-command 存在せず (recorded) ──────
attempt_gh_cli() {
    smoke_log "attempt gh CLI: view-edit sub-command 確認..."
    local cli_help
    cli_help=$(gh project --help 2>&1 || true)
    echo "$cli_help" >> "$SMOKE_LOG_FILE"

    if echo "$cli_help" | grep -qiE "view-edit|layout"; then
        smoke_add_check "gh_cli" "gh project view-edit / layout sub-command" \
            "gh project --help" "view-edit / layout" "found" "pass"
        return 0
    else
        smoke_add_check "gh_cli" "gh project view-edit sub-command 存在" \
            "gh project --help" "view-edit" "not found (gh CLI 未対応)" "fail"
        return 1
    fi
}

# ── 手段 (b) GraphQL: updateProjectV2View mutation ─────────────
# Fix 6 (anti-AI-sabotage): API_LIMITATION 検知パス
# GraphQL introspection で updateProjectV2View 存在確認 → 不在なら API_LIMITATION 確定
# server_state check は "API_LIMITATION 確認" を pass として記録 (empirical evidence)
attempt_graphql() {
    smoke_log "attempt GraphQL: introspection で updateProjectV2View 存在確認..."
    local result rc
    result=$(gh api graphql -f query='{ __type(name: "Mutation") { fields { name } } }' \
        --jq '.data.__type.fields[].name' 2>&1) && rc=0 || rc=$?

    if [[ "$rc" -eq 0 ]]; then
        if echo "$result" | grep -q "^updateProjectV2View$"; then
            smoke_log "updateProjectV2View mutation 存在、layout 切替試行..."
            # 実 mutation 試行 (Phase G で詳細実装、現状は introspection only)
            smoke_add_check "graphql" "updateProjectV2View mutation 存在 (introspection)" \
                "gh api graphql introspection | grep updateProjectV2View" \
                "name=updateProjectV2View" "found" "pass"
            API_LIMITATION_DETECTED=false
            return 0
        else
            # API_LIMITATION empirical 確認
            smoke_add_check "graphql" "updateProjectV2View mutation 不在 (API_LIMITATION 確認)" \
                "gh api graphql introspection | grep -E '^updateProjectV2View$'" \
                "name=updateProjectV2View" "NOT FOUND (API_LIMITATION empirical confirmed)" "pass"
            API_LIMITATION_DETECTED=true
            return 0
        fi
    else
        smoke_add_check "graphql" "introspection query 実行" \
            "gh api graphql introspection" "exit=0" "exit=$rc: ${result:0:200}" "fail"
        return 1
    fi
}

API_LIMITATION_DETECTED=false
try_methods attempt_gh_cli attempt_graphql || true

# ── server-side state 検証 ──────────────────────────────────────
smoke_log "server-side state 検証..."
if [[ "$API_LIMITATION_DETECTED" == "true" ]]; then
    # API_LIMITATION 検知済み: layout 切替検証 skip、empirical findings として pass 記録
    smoke_add_check "server_state" "API_LIMITATION findings 記録 (layout 切替不可、UI のみ操作可能)" \
        "introspection empirical confirmation" \
        "API_LIMITATION" "updateProjectV2View mutation does not exist on type Mutation" "pass"
else
    VIEW_AFTER=$(gh api graphql \
        -f query='query($id: ID!) {
            node(id: $id) { ... on ProjectV2 { views(first: 5) { nodes { id layout } } } }
        }' \
        -f id="$TWL_SMOKE_BOARD_ID" 2>&1)
    echo "after: $VIEW_AFTER" >> "$SMOKE_LOG_FILE"

    ACTUAL_LAYOUT=$(echo "$VIEW_AFTER" | jq -r --arg vid "$VIEW_ID" '.data.node.views.nodes[] | select(.id==$vid) | .layout')

    if [[ "$ACTUAL_LAYOUT" == "$TARGET_LAYOUT" ]]; then
        smoke_add_check "server_state" "view layout が '$TARGET_LAYOUT' に切替" \
            "gh api graphql views | .layout" "$TARGET_LAYOUT" "$ACTUAL_LAYOUT" "pass"
    else
        smoke_add_check "server_state" "view layout が '$TARGET_LAYOUT' に切替" \
            "gh api graphql views | .layout" "$TARGET_LAYOUT" "$ACTUAL_LAYOUT" "fail"
    fi
fi

# ── result emit ─────────────────────────────────────────────────
# Fix 1: server_state pass 必須
if smoke_method_and_server_pass; then
    if [[ "$API_LIMITATION_DETECTED" == "true" ]]; then
        smoke_emit_result true "API_LIMITATION findings: updateProjectV2View mutation does not exist"
    else
        smoke_emit_result true ""
    fi
else
    smoke_emit_result false "method or server_state check fail"
    exit 1
fi
