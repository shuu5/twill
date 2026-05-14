#!/usr/bin/env bash
# experiments/EXP-021-label-add-remove.smoke.sh
# EXP-021: repository label add/remove (2 手段)
#
# verify 対象:
#   test repo に label を add / delete
#   手段 (a) gh CLI: gh label create / gh label delete
#   手段 (b) GraphQL: createLabel / deleteLabel mutation
#
# verify_source: https://cli.github.com/manual/gh_label

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/smoke-common.sh"

SMOKE_EXP_ID="EXP-021"
SMOKE_VERIFY_SOURCE="https://cli.github.com/manual/gh_label"
LABEL_CLI="smoke-cli-$(date +%s)"
LABEL_GQL="smoke-gql-$(date +%s)"

# ── main ────────────────────────────────────────────────────────
smoke_parse_args "$@"
smoke_init_log
smoke_check_prereqs
smoke_ensure_board_env
smoke_trap_cleanup

# ── 手段 (a) gh CLI: gh label create ───────────────────────────
attempt_gh_cli_create() {
    smoke_log "attempt gh CLI: gh label create $LABEL_CLI..."
    local result rc
    result=$(gh label create "$LABEL_CLI" \
        --repo "$TWL_SMOKE_REPO_FULL" \
        --color "ededed" \
        --description "EXP-021 smoke (gh CLI)" 2>&1) && rc=0 || rc=$?
    echo "$result" >> "$SMOKE_LOG_FILE"

    if [[ "$rc" -eq 0 ]]; then
        smoke_add_check "gh_cli" "gh label create" \
            "gh label create $LABEL_CLI --repo $TWL_SMOKE_REPO_FULL" \
            "exit=0" "exit=0" "pass"
        return 0
    else
        smoke_add_check "gh_cli" "gh label create" \
            "gh label create" "exit=0" "exit=$rc: ${result:0:200}" "fail"
        return 1
    fi
}

# ── 手段 (b) GraphQL: createLabel mutation ─────────────────────
attempt_graphql_create() {
    smoke_log "attempt GraphQL: createLabel mutation..."
    local mutation result rc
    mutation='mutation($repoId: ID!, $name: String!, $color: String!) {
        createLabel(input: {repositoryId: $repoId, name: $name, color: $color}) {
            label { id name color }
        }
    }'

    # createLabel は preview header が必要 (feature preview)
    result=$(gh api graphql \
        --header "GraphQL-Features: projects_next_graphql" \
        -f query="$mutation" \
        -f repoId="$TWL_SMOKE_REPO_ID" \
        -f name="$LABEL_GQL" \
        -f color="cccccc" 2>&1) && rc=0 || rc=$?
    echo "$result" >> "$SMOKE_LOG_FILE"

    if [[ "$rc" -eq 0 ]] && echo "$result" | jq -e '.data.createLabel.label.name' >/dev/null 2>&1; then
        smoke_add_check "graphql" "createLabel mutation" \
            "gh api graphql createLabel" \
            "data.createLabel.label.name set" "${result:0:200}" "pass"
        return 0
    else
        smoke_add_check "graphql" "createLabel mutation" \
            "gh api graphql createLabel" \
            "data.createLabel.label.name" "exit=$rc: ${result:0:200}" "fail"
        return 1
    fi
}

try_methods attempt_gh_cli_create attempt_graphql_create || true

# ── server-side state: label list に含まれるか ─────────────────
smoke_log "server-side state 検証..."
LABELS_JSON=$(gh label list --repo "$TWL_SMOKE_REPO_FULL" --json name --limit 200 2>&1)
echo "labels: $LABELS_JSON" >> "$SMOKE_LOG_FILE"

# CLI または GraphQL のどちらかで作成された label が存在するか
if echo "$LABELS_JSON" | jq -e --arg n "$LABEL_CLI" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    smoke_add_check "server_state" "label '$LABEL_CLI' が repo に存在 (CLI 経由)" \
        "gh label list --repo $TWL_SMOKE_REPO_FULL --json name | jq '.[].name'" \
        "$LABEL_CLI" "found" "pass"
elif echo "$LABELS_JSON" | jq -e --arg n "$LABEL_GQL" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    smoke_add_check "server_state" "label '$LABEL_GQL' が repo に存在 (GraphQL 経由)" \
        "gh label list --repo $TWL_SMOKE_REPO_FULL --json name | jq '.[].name'" \
        "$LABEL_GQL" "found" "pass"
else
    smoke_add_check "server_state" "label add result" \
        "gh label list" "$LABEL_CLI または $LABEL_GQL" "neither found" "fail"
fi

# ── delete 検証 (CLI で先に作成された label のみ削除確認) ──────
if echo "$LABELS_JSON" | jq -e --arg n "$LABEL_CLI" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    smoke_log "delete 検証: $LABEL_CLI"
    if gh label delete "$LABEL_CLI" --repo "$TWL_SMOKE_REPO_FULL" --yes >> "$SMOKE_LOG_FILE" 2>&1; then
        # 削除後 list で消えたか確認
        AFTER_DELETE=$(gh label list --repo "$TWL_SMOKE_REPO_FULL" --json name --limit 200 2>&1)
        if ! echo "$AFTER_DELETE" | jq -e --arg n "$LABEL_CLI" '.[] | select(.name==$n)' >/dev/null 2>&1; then
            smoke_add_check "server_state" "label '$LABEL_CLI' が削除された" \
                "gh label delete + gh label list" "$LABEL_CLI not in list" "deleted" "pass"
        else
            smoke_add_check "server_state" "label delete" \
                "gh label delete" "$LABEL_CLI removed" "still in list" "fail"
        fi
    else
        smoke_add_check "server_state" "label delete" \
            "gh label delete" "exit=0" "exit non-zero" "fail"
    fi
fi

# ── Fix 10: GraphQL 経由 label も cleanup ──────────────────────
# (CLI label は delete 検証で削除済み、GraphQL 経由作成 label が残存する case を fix)
for _lbl in "$LABEL_CLI" "$LABEL_GQL"; do
    if gh label list --repo "$TWL_SMOKE_REPO_FULL" --json name --limit 200 2>/dev/null \
        | jq -e --arg n "$_lbl" '.[] | select(.name==$n)' >/dev/null 2>&1; then
        smoke_log "extra cleanup: $_lbl"
        gh label delete "$_lbl" --repo "$TWL_SMOKE_REPO_FULL" --yes \
            >> "$SMOKE_LOG_FILE" 2>&1 || true
    fi
done

# ── result emit ─────────────────────────────────────────────────
if smoke_method_and_server_pass; then
    smoke_emit_result true ""
else
    smoke_emit_result false "method or server_state check fail"
    exit 1
fi
