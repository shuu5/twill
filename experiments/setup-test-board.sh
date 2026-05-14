#!/usr/bin/env bash
# experiments/setup-test-board.sh
# Phase F-4 anti-sabotage smoke infrastructure.
#
# 用途:
#   - shuu5 user owner で test project board + test repo を新規作成
#   - smoke.sh から source 経由 or run-all.sh から事前 setup として呼ばれる
#   - 結果として env 変数を stdout に `KEY=VALUE` 形式で emit
#
# 使用法:
#   # standalone (smoke.sh が自前 setup):
#   eval "$(bash experiments/setup-test-board.sh)"
#
#   # run-all.sh 経由:
#   eval "$(bash experiments/setup-test-board.sh)" && \
#     for smoke in experiments/EXP-NNN-*.smoke.sh; do bash "$smoke"; done
#
# 出力 (stdout、export 形式):
#   export TWL_SMOKE_BOARD_NUM=N
#   export TWL_SMOKE_BOARD_ID=PVT_xxx
#   export TWL_SMOKE_BOARD_URL=https://...
#   export TWL_SMOKE_BOARD_OWNER=shuu5
#   export TWL_SMOKE_BOARD_NAME=twl-smoke-test-<timestamp>
#   export TWL_SMOKE_REPO_FULL=shuu5/twl-smoke-test-repo
#   export TWL_SMOKE_REPO_ID=R_xxx
#   export TWL_SMOKE_STATUS_FIELD_ID=PVTSSF_xxx
#   export TWL_SMOKE_ISSUE_ITEM_ID=PVTI_xxx
#
# 失敗時:
#   exit 1 + stderr にエラー詳細

set -euo pipefail

OWNER="shuu5"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
BOARD_NAME="twl-smoke-test-${TIMESTAMP}"
REPO_NAME="twl-smoke-test-repo"
REPO_FULL="${OWNER}/${REPO_NAME}"

log() { echo "[setup-test-board] $*" >&2; }

# Fix 3: setup 中途 failure 時の partial cleanup
# board 作成成功後に何かが failed したら作成済 board を削除 (cleanup 機会喪失防止)
BOARD_ID=""
_setup_cleanup_on_failure() {
    local rc=$?
    [[ $rc -eq 0 ]] && return 0
    if [[ -n "$BOARD_ID" && "$BOARD_ID" == PVT_* ]]; then
        log "setup failed (rc=$rc)、partial board 削除中: $BOARD_ID"
        gh api graphql -f query='mutation($id:ID!){deleteProjectV2(input:{projectId:$id}){projectV2{id}}}' \
            -f id="$BOARD_ID" >/dev/null 2>&1 || \
            log "partial board 削除失敗、手動 cleanup 必要: $BOARD_ID"
    fi
    return $rc
}
trap '_setup_cleanup_on_failure' EXIT INT TERM

# ── 前提チェック ────────────────────────────────────────────────
for cmd in gh jq; do
    command -v "$cmd" >/dev/null 2>&1 || {
        log "error: $cmd required"
        exit 1
    }
done

# project scope 確認
if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
    log "error: gh auth requires project scope. Run: gh auth refresh -s project"
    exit 1
fi

# ── owner node ID 取得 ──────────────────────────────────────────
log "owner node ID 取得中..."
OWNER_ID=$(gh api graphql \
    -f query='query($login: String!) { user(login: $login) { id } }' \
    -f login="$OWNER" \
    --jq '.data.user.id')

[[ -n "$OWNER_ID" ]] || { log "error: owner ID 取得失敗"; exit 1; }
log "owner ID: $OWNER_ID"

# ── test repo 確保 (既存なら reuse、なければ create) ────────────
log "test repo 確保中: $REPO_FULL"
if gh repo view "$REPO_FULL" >/dev/null 2>&1; then
    log "test repo 既存: $REPO_FULL (reuse)"
else
    log "test repo 作成中: $REPO_FULL"
    gh repo create "$REPO_FULL" --private --description "twl smoke test (auto-cleanup)" >/dev/null
fi

REPO_ID=$(gh api graphql \
    -f query='query($owner: String!, $name: String!) {
        repository(owner: $owner, name: $name) { id }
    }' \
    -f owner="$OWNER" \
    -f name="$REPO_NAME" \
    --jq '.data.repository.id')

[[ -n "$REPO_ID" ]] || { log "error: repo ID 取得失敗"; exit 1; }
log "repo ID: $REPO_ID"

# ── board 作成 (createProjectV2 mutation) ───────────────────────
log "board 作成中: $BOARD_NAME"
CREATE_RESULT=$(gh api graphql \
    -f query='mutation($ownerId: ID!, $title: String!) {
        createProjectV2(input: {ownerId: $ownerId, title: $title}) {
            projectV2 { id number url }
        }
    }' \
    -f ownerId="$OWNER_ID" \
    -f title="$BOARD_NAME")

BOARD_ID=$(echo "$CREATE_RESULT" | jq -r '.data.createProjectV2.projectV2.id // empty')
BOARD_NUM=$(echo "$CREATE_RESULT" | jq -r '.data.createProjectV2.projectV2.number // empty')
BOARD_URL=$(echo "$CREATE_RESULT" | jq -r '.data.createProjectV2.projectV2.url // empty')

[[ -n "$BOARD_ID" && -n "$BOARD_NUM" ]] || {
    log "error: board 作成失敗"
    log "response: $CREATE_RESULT"
    exit 1
}

# safety guard: board ID は PVT_ prefix
[[ "$BOARD_ID" == PVT_* ]] || {
    log "error: board ID format unexpected: $BOARD_ID (safety guard)"
    exit 1
}

log "board 作成完了: num=$BOARD_NUM id=$BOARD_ID"
log "board URL: $BOARD_URL"

# ── repo を board に link ───────────────────────────────────────
log "repo を board に link 中..."
gh api graphql \
    -f query='mutation($projectId: ID!, $repositoryId: ID!) {
        linkProjectV2ToRepository(input: {projectId: $projectId, repositoryId: $repositoryId}) {
            repository { id }
        }
    }' \
    -f projectId="$BOARD_ID" \
    -f repositoryId="$REPO_ID" \
    --jq '.data.linkProjectV2ToRepository.repository.id' >/dev/null

# ── test issue 作成 ─────────────────────────────────────────────
log "test issue 作成中..."
ISSUE_URL=$(gh issue create \
    --repo "$REPO_FULL" \
    --title "smoke test issue (EXP-015)" \
    --body "Phase F-4 smoke test target. Auto-cleanup on Phase F-5." \
    2>/dev/null | tail -1)

[[ -n "$ISSUE_URL" ]] || { log "error: test issue 作成失敗"; exit 1; }
log "test issue: $ISSUE_URL"

# ── test issue を board に追加 ──────────────────────────────────
log "test issue を board に追加中..."
ISSUE_ITEM_ID=$(gh project item-add "$BOARD_NUM" \
    --owner "$OWNER" \
    --url "$ISSUE_URL" \
    --format json \
    | jq -r '.id')

[[ -n "$ISSUE_ITEM_ID" ]] || { log "error: item-add 失敗"; exit 1; }
log "item ID: $ISSUE_ITEM_ID"

# ── Status field id 取得 ────────────────────────────────────────
log "Status field id 取得中..."
STATUS_FIELD_ID=$(gh project field-list "$BOARD_NUM" --owner "$OWNER" --format json \
    | jq -r '.fields[] | select(.name == "Status") | .id')

[[ -n "$STATUS_FIELD_ID" ]] || { log "error: Status field id 取得失敗"; exit 1; }
log "Status field ID: $STATUS_FIELD_ID"

# ── env 変数を stdout に emit ───────────────────────────────────
cat <<EOF
export TWL_SMOKE_BOARD_NUM=$BOARD_NUM
export TWL_SMOKE_BOARD_ID=$BOARD_ID
export TWL_SMOKE_BOARD_URL=$BOARD_URL
export TWL_SMOKE_BOARD_OWNER=$OWNER
export TWL_SMOKE_BOARD_NAME=$BOARD_NAME
export TWL_SMOKE_REPO_FULL=$REPO_FULL
export TWL_SMOKE_REPO_ID=$REPO_ID
export TWL_SMOKE_STATUS_FIELD_ID=$STATUS_FIELD_ID
export TWL_SMOKE_ISSUE_ITEM_ID=$ISSUE_ITEM_ID
EOF

log "setup 完了"
