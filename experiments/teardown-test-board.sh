#!/usr/bin/env bash
# experiments/teardown-test-board.sh
# Phase F-4 anti-sabotage smoke cleanup.
#
# 用途:
#   - setup-test-board.sh で作成した board + repo を削除
#   - Phase F-5 末で実行、または smoke.sh の trap cleanup から呼ばれる
#
# 使用法:
#   # env 変数経由 (smoke.sh 自前 setup の trap cleanup):
#   TWL_SMOKE_BOARD_ID=... TWL_SMOKE_REPO_FULL=... bash teardown-test-board.sh
#
#   # 引数経由 (Phase F-5 末):
#   bash teardown-test-board.sh <board_id> <repo_full>
#
# 引数優先順位: arg > env
#
# safety guard: board ID が PVT_ prefix でなければ exit 1 (誤削除防止)

set +e  # 削除失敗時も続行 (best-effort cleanup)

BOARD_ID="${1:-${TWL_SMOKE_BOARD_ID:-}}"
REPO_FULL="${2:-${TWL_SMOKE_REPO_FULL:-}}"

log() { echo "[teardown-test-board] $*" >&2; }

if [[ -z "$BOARD_ID" && -z "$REPO_FULL" ]]; then
    log "warning: BOARD_ID / REPO_FULL 両方未指定、何もしない"
    exit 0
fi

# ── board 削除 ──────────────────────────────────────────────────
if [[ -n "$BOARD_ID" ]]; then
    # safety guard
    if [[ "$BOARD_ID" != PVT_* ]]; then
        log "error: board ID format unexpected: $BOARD_ID (safety guard、削除しない)"
    else
        log "board 削除中: $BOARD_ID"
        for attempt in 1 2 3; do
            DELETE_RESULT=$(gh api graphql \
                -f query='mutation($projectId: ID!) {
                    deleteProjectV2(input: {projectId: $projectId}) {
                        projectV2 { id }
                    }
                }' \
                -f projectId="$BOARD_ID" 2>&1) && {
                log "board 削除完了 (attempt=$attempt)"
                break
            }
            log "board 削除失敗 (attempt=$attempt): $DELETE_RESULT"
            sleep $((attempt * 2))
        done
    fi
fi

# ── repo 削除 ───────────────────────────────────────────────────
if [[ -n "$REPO_FULL" ]]; then
    log "repo 削除中: $REPO_FULL"
    # safety guard: REPO_FULL は shuu5/twl-smoke-test-* 形式必須
    if [[ "$REPO_FULL" != shuu5/twl-smoke-test* ]]; then
        log "error: repo format unexpected: $REPO_FULL (safety guard、削除しない)"
    else
        gh repo delete "$REPO_FULL" --yes 2>&1 | head -3 >&2 || {
            log "repo 削除失敗、手動 cleanup 必要: gh repo delete $REPO_FULL --yes"
        }
    fi
fi

log "teardown 完了"
