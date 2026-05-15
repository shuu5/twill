#!/usr/bin/env bash
# spawn-tmux.sh — 3 階層共通 tmux spawn helper (Phase 1 PoC C2 2026-05-15、Phase 6 review fix 統合)
#
# 仕様: spawn-protocol.html §3 (verified tmux flags、3 階層 spawn pattern)
# verified: tmux new-window -d -n -c -e flags (tmux man verified、EXP-016)
# Phase I 2026-05-15 確定:
#   - TWL_PHASER_NAME env (tmux new-window -e、tmux 3.x 以降必須) で atomic SKILL.md Step 3 mailbox identifier 注入
#   - _wait_session_ready 3 条件 AND (pane_in_mode=0 + 'Press up to edit' 不在 + idle 持続)
#
# Phase 6 review fix (本 file):
#   - C-3: tmux 3.x version check 追加 (tmux 1.x/2.x には new-window -e flag なし、起動時 fail-fast)
#   - C-1 (JSON injection): _emit_admin で jq -nc --arg を使用、文字列 interpolation 廃止
#
# usage: spawn-tmux.sh --window-name <name> --skill <namespaced> [--args <str>] [--cwd <path>] --mailbox-from <name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=mailbox.sh
source "$SCRIPT_DIR/mailbox.sh"

_check_tmux_version() {
    # tmux 3.x 以降必須 (-e flag は 3.0 で追加)、起動時 fail-fast
    local version
    version=$(tmux -V 2>/dev/null | awk '{print $2}')
    [ -n "$version" ] || _fail "tmux not found in PATH"
    local major
    major=$(echo "$version" | cut -d. -f1)
    if [ "$major" -lt 3 ] 2>/dev/null; then
        _fail "tmux 3.x required for new-window -e flag (current: $version)"
    fi
}

_wait_session_ready() {
    # 3 条件 AND 判定 (CLAUDE.md feedback_inject_queue_verification 反映、Phase I 2026-05-15)
    local window="$1"; local timeout="$2"; local elapsed=0
    local idle_min_sec="${IDLE_MIN_SEC:-2}"
    local idle_accumulated=0

    while [ "$elapsed" -lt "$timeout" ]; do
        # (a) pane_in_mode=0 (idle、edit mode でない)
        local in_mode
        in_mode=$(tmux list-windows -a -F '#{window_name}|#{pane_in_mode}' 2>/dev/null \
                    | grep "^${window}|" | cut -d'|' -f2 || echo "")
        if [ "$in_mode" != "0" ]; then
            idle_accumulated=0; sleep 1; elapsed=$((elapsed+1)); continue
        fi

        # (b) "Press up to edit queued" 不在 (旧 inject の queue 残留検知)
        local pane_tail
        pane_tail=$(tmux capture-pane -t "$window" -p -S -5 2>/dev/null | tail -3 || echo "")
        if echo "$pane_tail" | grep -q "Press up to edit"; then
            # queue 残留 → Enter 送信して flush し再判定
            tmux send-keys -t "$window" Enter 2>/dev/null || true
            idle_accumulated=0; sleep 1; elapsed=$((elapsed+1)); continue
        fi

        # (c) idle 持続時間 (default 2s、startup 中 false ready 防止)
        idle_accumulated=$((idle_accumulated+1))
        if [ "$idle_accumulated" -ge "$idle_min_sec" ]; then
            return 0
        fi
        sleep 1; elapsed=$((elapsed+1))
    done
    return 1
}

_emit_admin() {
    # Phase 6 review C-1 fix: jq で JSON 構築、文字列 interpolation 廃止 (injection 回避)
    local from="$1" event="$2"
    shift 2
    # 残り引数を key=value pair として detail object に組み立て (jq -nc --arg ...)
    local jq_args=() jq_obj_keys=()
    while [ $# -ge 2 ]; do
        local key="$1" value="$2"; shift 2
        jq_args+=(--arg "$key" "$value")
        jq_obj_keys+=("$key: \$$key")
    done
    local obj_expr
    obj_expr="{$(IFS=,; echo "${jq_obj_keys[*]}")}"
    local detail
    detail=$(jq -nc "${jq_args[@]}" "$obj_expr")
    mailbox_emit "$from" "administrator" "$event" "$detail"
}

_fail() { echo "spawn-tmux.sh: $*" >&2; exit 1; }

main() {
    local window_name="" skill="" args="" cwd="" mailbox_from=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --window-name) window_name="$2"; shift 2 ;;
            --skill)       skill="$2"; shift 2 ;;
            --args)        args="$2"; shift 2 ;;
            --cwd)         cwd="$2"; shift 2 ;;
            --mailbox-from) mailbox_from="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # 必須引数 check
    [ -n "$window_name" ] || _fail "--window-name required"
    [ -n "$skill" ]       || _fail "--skill required"
    [ -n "$mailbox_from" ] || _fail "--mailbox-from required"

    # 0. tmux version check (Phase 6 review C-3 fix)
    _check_tmux_version

    # 1. window 名 length check (50 文字上限、tmux 制約)
    [ "${#window_name}" -le 50 ] || _fail "window name too long (>50): $window_name"

    # 2. 既存 window 確認 (Inv I-1 idempotent guard)
    if tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -qx "$window_name"; then
        _emit_admin "$mailbox_from" "spawn-skip" \
            "window" "$window_name" "reason" "already exists"
        return 0
    fi

    # 3. plugin dir 解決
    local plugin_dir="${TWILL_PLUGIN_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}/plugins/twl}"
    local work_cwd="${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"

    # 4. tmux new-window (detached、cwd、env)
    # TWL_PHASER_NAME は atomic SKILL.md Step 3 が mailbox path 解決に使用 (Phase I 確定)
    tmux new-window \
        -d \
        -n "$window_name" \
        -c "$work_cwd" \
        -e "TWL_PHASER_NAME=$window_name" \
        -- claude --plugin-dir "$plugin_dir"

    # 5. session ready 待ち (30s timeout、3 条件 AND)
    _wait_session_ready "$window_name" 30 \
        || _fail "session not ready after 30s: $window_name"

    # 6. /twl:<skill> <args> inject
    local cmd="/${skill} ${args:-}"
    tmux send-keys -t "$window_name" "$cmd" Enter

    # 7. spawn-completed mail emit (jq-based JSON 構築、injection 回避)
    _emit_admin "$mailbox_from" "spawn-completed" \
        "window" "$window_name" "skill" "$skill"
}

# direct exec (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
