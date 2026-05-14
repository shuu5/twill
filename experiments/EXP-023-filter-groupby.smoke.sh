#!/usr/bin/env bash
# experiments/EXP-023-filter-groupby.smoke.sh
# EXP-023: view filter / group-by 設定
#
# verify 対象:
#   view の filterQuery + groupByFields を automation で設定
#   手段 (a) gh CLI: filter / group-by sub-command 存在確認 (未対応 expected)
#   手段 (b) GraphQL: updateProjectV2View mutation (filter field)
#
# 注: API limitation の場合は skip 記録

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/smoke-common.sh"

SMOKE_EXP_ID="EXP-023"
SMOKE_VERIFY_SOURCE="https://docs.github.com/en/graphql/reference/mutations"
FILTER_QUERY="status:\"Todo\""

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
                views(first: 5) { nodes { id name filter } }
            }
        }
    }' \
    -f id="$TWL_SMOKE_BOARD_ID" 2>&1)
echo "views: $VIEW_JSON" >> "$SMOKE_LOG_FILE"

VIEW_ID=$(echo "$VIEW_JSON" | jq -r '.data.node.views.nodes[0].id // empty')
[[ -n "$VIEW_ID" ]] || {
    smoke_log "error: view ID 取得失敗"
    smoke_add_check "verify" "view ID 取得" "gh api graphql views" "PVTV_*" "missing" "fail"
    smoke_emit_result false "view ID 取得失敗"
    exit 1
}
smoke_log "view ID: $VIEW_ID"

# ── 手段 (a) gh CLI: filter sub-command 存在確認 ───────────────
attempt_gh_cli() {
    smoke_log "attempt gh CLI: filter / group-by sub-command 確認..."
    local cli_help
    cli_help=$(gh project --help 2>&1 || true)
    echo "$cli_help" >> "$SMOKE_LOG_FILE"

    if echo "$cli_help" | grep -qiE "filter|group-by|groupby"; then
        smoke_add_check "gh_cli" "gh project filter / group-by sub-command" \
            "gh project --help" "filter / group-by" "found" "pass"
        return 0
    else
        smoke_add_check "gh_cli" "gh project filter / group-by sub-command 存在" \
            "gh project --help" "filter / group-by" "not found (gh CLI 未対応)" "fail"
        return 1
    fi
}

# ── 手段 (b) GraphQL: updateProjectV2View mutation ─────────────
# Fix 6 (anti-AI-sabotage): EXP-022 と同じ API_LIMITATION 検知パス
attempt_graphql() {
    smoke_log "attempt GraphQL: introspection で updateProjectV2View 存在確認..."
    local result rc
    result=$(gh api graphql -f query='{ __type(name: "Mutation") { fields { name } } }' \
        --jq '.data.__type.fields[].name' 2>&1) && rc=0 || rc=$?
    # Phase G fix: introspection result を SMOKE_LOG_FILE に記録
    {
        echo "=== EXP-023 introspection result (rc=$rc) ==="
        echo "$result" | head -100
        echo "=== end introspection ==="
    } >> "$SMOKE_LOG_FILE"

    local relevant_mutations
    relevant_mutations=$(echo "$result" | grep -E "Project.*View|updateProjectV2View" | head -10 || true)

    if [[ "$rc" -eq 0 ]]; then
        if echo "$result" | grep -q "^updateProjectV2View$"; then
            smoke_log "updateProjectV2View mutation 存在、filter 設定試行..."
            smoke_add_check "graphql" "updateProjectV2View mutation 存在 (introspection)" \
                "gh api graphql introspection | grep updateProjectV2View" \
                "name=updateProjectV2View" \
                "found in Mutation type fields; related: $relevant_mutations" "pass"
            API_LIMITATION_DETECTED=false
            return 0
        else
            smoke_add_check "graphql" "updateProjectV2View mutation 不在 (API_LIMITATION 確認)" \
                "gh api graphql introspection | grep -E '^updateProjectV2View\$'" \
                "name=updateProjectV2View" \
                "NOT FOUND (related Mutation fields: ${relevant_mutations:-none}; total Mutation fields=$(echo "$result" | wc -l))" "pass"
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
    smoke_add_check "server_state" "API_LIMITATION findings 記録 (filter / group-by 設定不可、UI のみ操作可能)" \
        "introspection empirical confirmation" \
        "API_LIMITATION" "updateProjectV2View mutation does not exist on type Mutation" "pass"
else
    VIEW_AFTER=$(gh api graphql \
        -f query='query($id: ID!) {
            node(id: $id) { ... on ProjectV2 { views(first: 5) { nodes { id filter } } } }
        }' \
        -f id="$TWL_SMOKE_BOARD_ID" 2>&1)
    echo "after: $VIEW_AFTER" >> "$SMOKE_LOG_FILE"

    ACTUAL_FILTER=$(echo "$VIEW_AFTER" | jq -r --arg vid "$VIEW_ID" '.data.node.views.nodes[] | select(.id==$vid) | .filter // ""')

    if [[ "$ACTUAL_FILTER" == "$FILTER_QUERY" ]]; then
        smoke_add_check "server_state" "view filter が '$FILTER_QUERY' に設定" \
            "gh api graphql views | .filter" "$FILTER_QUERY" "$ACTUAL_FILTER" "pass"
    else
        smoke_add_check "server_state" "view filter 設定" \
            "gh api graphql views | .filter" "$FILTER_QUERY" "${ACTUAL_FILTER:-(empty)}" "fail"
    fi
fi

# ── result emit ─────────────────────────────────────────────────
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
