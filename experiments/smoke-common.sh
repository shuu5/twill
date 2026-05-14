#!/usr/bin/env bash
# experiments/smoke-common.sh
# Phase F-4 anti-sabotage smoke helper library.
#
# 用途:
#   - 各 EXP-NNN-*.smoke.sh が source する共通 helper
#   - argparse / log capture / verify_checks / result emit / try_methods
#   - run-all.sh 経由・standalone 両対応
#
# 使用例 (smoke.sh 内):
#   source "$SCRIPT_DIR/smoke-common.sh"
#   smoke_parse_args "$@"
#   smoke_init_log
#   smoke_ensure_board_env  # standalone 時に自前 setup
#   smoke_trap_cleanup
#   smoke_add_check "method=gh_cli desc='item-edit exit 0' command='gh project item-edit ...' \
#                    expected='exit=0' actual=\"$result\" status=pass"
#   smoke_emit_result true ""
#
# verify_checks schema (per entry):
#   {
#     "method": "gh_cli" | "graphql" | "server_state" | "verify",
#     "description": "human readable",
#     "command": "実行 command (truncated)",
#     "expected_grep": "期待 pattern",
#     "actual_output": "実 output (truncated 200 chars)",
#     "status": "pass" | "fail" | "skip"
#   }

# 注意: caller が source する側で set -euo pipefail を呼ぶ前提

# ── グローバル状態 ──────────────────────────────────────────────
SMOKE_LOG_DIR=""
SMOKE_RUN_ID=""
SMOKE_EXP_ID=""
SMOKE_LOG_FILE=""
SMOKE_VERIFY_CHECKS_JSON="[]"
SMOKE_SELF_SETUP=false
SMOKE_VERIFY_SOURCE=""

smoke_log() {
    echo "[${SMOKE_EXP_ID:-smoke}] $*" >&2
    [[ -n "$SMOKE_LOG_FILE" ]] && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$SMOKE_LOG_FILE"
    return 0
}

# ── argparse ────────────────────────────────────────────────────
smoke_parse_args() {
    # Usage: smoke_parse_args "$@"
    # Sets: SMOKE_LOG_DIR, SMOKE_RUN_ID
    # smoke.sh が事前に SMOKE_EXP_ID を設定する想定
    SMOKE_LOG_DIR="${TMPDIR:-/tmp}/twl-smoke-$$"
    SMOKE_RUN_ID="standalone-$(date -u +%Y%m%d-%H%M%S)"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --log-dir) SMOKE_LOG_DIR="$2"; shift 2 ;;
            --run-id)  SMOKE_RUN_ID="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 [--log-dir <dir>] [--run-id <id>]" >&2
                exit 0
                ;;
            *) echo "unknown option: $1" >&2; exit 2 ;;
        esac
    done
}

# ── log init ────────────────────────────────────────────────────
smoke_init_log() {
    [[ -n "$SMOKE_EXP_ID" ]] || { echo "SMOKE_EXP_ID not set" >&2; exit 2; }
    mkdir -p "$SMOKE_LOG_DIR"
    SMOKE_LOG_FILE="${SMOKE_LOG_DIR}/${SMOKE_EXP_ID}.log"
    : > "$SMOKE_LOG_FILE"  # truncate
    smoke_log "log init: $SMOKE_LOG_FILE"
}

smoke_log_hash() {
    # 出力: sha256:<hex full>
    if [[ -f "$SMOKE_LOG_FILE" ]]; then
        echo "sha256:$(sha256sum "$SMOKE_LOG_FILE" | awk '{print $1}')"
    else
        echo "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    fi
}

# ── 前提チェック ────────────────────────────────────────────────
smoke_check_prereqs() {
    for cmd in gh jq sha256sum; do
        command -v "$cmd" >/dev/null 2>&1 || {
            smoke_log "error: $cmd required"
            exit 2
        }
    done

    # project scope 確認
    if ! gh project list --owner @me --limit 1 >/dev/null 2>&1; then
        smoke_log "error: gh auth requires project scope. Run: gh auth refresh -s project"
        exit 2
    fi
}

# ── board env 確保 ──────────────────────────────────────────────
smoke_ensure_board_env() {
    # TWL_SMOKE_BOARD_NUM が未設定なら setup-test-board.sh を実行
    if [[ -z "${TWL_SMOKE_BOARD_NUM:-}" ]]; then
        SMOKE_SELF_SETUP=true
        smoke_log "standalone 実行: setup-test-board.sh を実行..."
        local setup_script
        setup_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-test-board.sh"
        local setup_output
        setup_output=$(bash "$setup_script" 2>>"$SMOKE_LOG_FILE") || {
            smoke_log "error: setup-test-board.sh failed"
            return 1
        }
        eval "$setup_output"
        smoke_log "self-setup 完了: BOARD_NUM=$TWL_SMOKE_BOARD_NUM BOARD_ID=$TWL_SMOKE_BOARD_ID"
    else
        smoke_log "既存 board env reuse: BOARD_NUM=$TWL_SMOKE_BOARD_NUM"
    fi
}

# ── trap cleanup ────────────────────────────────────────────────
smoke_trap_cleanup() {
    # SELF_SETUP の場合のみ board 削除を行う
    # Fix 2: SIGTERM/SIGINT でも cleanup を発火させる
    trap '_smoke_cleanup_handler $?' EXIT INT TERM
}

_smoke_cleanup_handler() {
    local rc="$1"
    if [[ "$SMOKE_SELF_SETUP" == "true" && -n "${TWL_SMOKE_BOARD_ID:-}" ]]; then
        smoke_log "cleanup: board + repo 削除中..."
        local teardown_script
        teardown_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/teardown-test-board.sh"
        TWL_SMOKE_BOARD_ID="$TWL_SMOKE_BOARD_ID" \
        TWL_SMOKE_REPO_FULL="${TWL_SMOKE_REPO_FULL:-}" \
            bash "$teardown_script" 2>>"$SMOKE_LOG_FILE" || true
    fi
    # Fix 5: EXIT trap 内で return は no-op、exit で smoke.sh の exit code を保持
    exit "$rc"
}

# ── verify_checks ───────────────────────────────────────────────
smoke_add_check() {
    # Usage: smoke_add_check <method> <description> <command> <expected_grep> <actual_output> <status>
    # status: pass | fail | skip
    local method="$1"
    local description="$2"
    local command="$3"
    local expected_grep="$4"
    local actual_output="$5"
    local status="$6"

    # truncate actual_output to 200 chars
    local actual_trunc
    actual_trunc="${actual_output:0:200}"

    # truncate command to 200 chars
    local command_trunc
    command_trunc="${command:0:200}"

    local entry
    entry=$(jq -n \
        --arg method "$method" \
        --arg desc "$description" \
        --arg cmd "$command_trunc" \
        --arg expected "$expected_grep" \
        --arg actual "$actual_trunc" \
        --arg status "$status" \
        '{method:$method, description:$desc, command:$cmd, expected_grep:$expected, actual_output:$actual, status:$status}')

    SMOKE_VERIFY_CHECKS_JSON=$(echo "$SMOKE_VERIFY_CHECKS_JSON" | jq --argjson e "$entry" '. + [$e]')
    smoke_log "check added: method=$method status=$status desc=\"$description\""
}

smoke_all_checks_pass() {
    # 1 件以上の pass がある AND fail が 0 件
    local pass_count fail_count
    pass_count=$(echo "$SMOKE_VERIFY_CHECKS_JSON" | jq '[.[] | select(.status=="pass")] | length')
    fail_count=$(echo "$SMOKE_VERIFY_CHECKS_JSON" | jq '[.[] | select(.status=="fail")] | length')
    [[ "$pass_count" -ge 1 && "$fail_count" -eq 0 ]]
}

smoke_any_method_succeeded() {
    # method gh_cli or graphql が status=pass を 1 件以上含む
    local count
    count=$(echo "$SMOKE_VERIFY_CHECKS_JSON" \
        | jq '[.[] | select((.method=="gh_cli" or .method=="graphql") and .status=="pass")] | length')
    [[ "$count" -ge 1 ]]
}

# Fix 1 (anti-AI-sabotage): try_methods 使用の smoke で必須
# method (gh_cli or graphql) と server_state の **両方** に pass が必要
# AI が gh_cli check を偽 pass にしても server_state pass がなければ smoke pass にならない
# 注: try_methods は first-success semantics で 1 method fail は容認 (例: gh_cli fail → graphql pass)
# critical な fail (server_state / verify) は 0 件必須
smoke_method_and_server_pass() {
    local method_pass server_pass critical_fail
    method_pass=$(echo "$SMOKE_VERIFY_CHECKS_JSON" \
        | jq '[.[] | select((.method=="gh_cli" or .method=="graphql") and .status=="pass")] | length')
    server_pass=$(echo "$SMOKE_VERIFY_CHECKS_JSON" \
        | jq '[.[] | select(.method=="server_state" and .status=="pass")] | length')
    critical_fail=$(echo "$SMOKE_VERIFY_CHECKS_JSON" \
        | jq '[.[] | select((.method=="server_state" or .method=="verify") and .status=="fail")] | length')
    [[ "$method_pass" -ge 1 && "$server_pass" -ge 1 && "$critical_fail" -eq 0 ]]
}

# ── try_methods (first-success semantics) ──────────────────────
try_methods() {
    # Usage: try_methods <method1_func> <method2_func> ...
    # 各 func は 0 exit で success、非 0 で fail
    # 最初に success した method で stop、後続は skip
    # 各 func 内で smoke_add_check を呼ぶ責務
    # Fix 4: $? は if/else ブロック後で stale (常に 1)、func 直後 rc 変数 capture
    local func func_rc
    for func in "$@"; do
        smoke_log "try: $func"
        if "$func"; then
            smoke_log "success: $func"
            return 0
        else
            func_rc=$?
            smoke_log "fail: $func (rc=$func_rc)"
        fi
    done
    smoke_log "all methods failed"
    return 1
}

# ── result emit ─────────────────────────────────────────────────
smoke_emit_result() {
    # Usage: smoke_emit_result <pass: true|false> <reason>
    # stdout: result JSON
    local pass="$1"
    local reason="$2"

    local log_hash
    log_hash=$(smoke_log_hash)

    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    jq -n \
        --arg exp_id "$SMOKE_EXP_ID" \
        --arg run_id "$SMOKE_RUN_ID" \
        --arg ts "$ts" \
        --argjson pass "$pass" \
        --arg reason "$reason" \
        --arg verify_source "$SMOKE_VERIFY_SOURCE" \
        --arg log_hash "$log_hash" \
        --arg log_file "$SMOKE_LOG_FILE" \
        --argjson vc "$SMOKE_VERIFY_CHECKS_JSON" \
        '{
            exp_id: $exp_id,
            run_id: $run_id,
            ts: $ts,
            pass: $pass,
            reason: $reason,
            verify_source: $verify_source,
            log_hash: $log_hash,
            log_file: $log_file,
            verify_checks: $vc
        }'
}

# ── gh API retry wrapper ────────────────────────────────────────
gh_with_retry() {
    # Usage: gh_with_retry <max_retries> <delay_base> gh <args...>
    local max_retries="$1"
    local delay_base="$2"
    shift 2

    local attempt=0
    local rc=0
    while (( attempt < max_retries )); do
        "$@" && return 0
        rc=$?
        attempt=$((attempt + 1))
        if (( attempt < max_retries )); then
            local delay=$((delay_base * (2 ** (attempt - 1))))
            smoke_log "gh retry $attempt/$max_retries after ${delay}s (rc=$rc)"
            sleep "$delay"
        fi
    done
    return "$rc"
}
