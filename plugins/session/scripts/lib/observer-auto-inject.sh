#!/usr/bin/env bash
# observer-auto-inject.sh - AskUserQuestion menu 自動 inject ヘルパー (#1145)
#
# 呼び出し方:
#   source observer-auto-inject.sh
#   auto_inject_menu <window> <pane_content> [thinking=<indicator>]
#
# OBSERVER_AUTO_INJECT_ENABLE=1 の場合のみ動作する（opt-in）。
# 依存: tmux, jq, flock
# 注意: source される前提のため set -euo pipefail は設定しない
# stuck-patterns.yaml SSoT ローダー (#1582)
_STUCK_PATTERNS_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../../twl/scripts/lib/stuck-patterns-lib.sh"
# shellcheck source=/dev/null
[[ -f "${_STUCK_PATTERNS_LIB}" ]] && source "${_STUCK_PATTERNS_LIB}" || true

# --- 定数 ---

# menu option regex（SSoT: pitfalls-catalog.md §2.5）
_MENU_OPT_RE='^[[:space:]❯►▶→]*[1-9][0-9]*[.):] .+$'

# deny-pattern（ERE, case-insensitive）
_DENY_RE='(delete|remove|reset|destroy|drop|wipe|purge|truncate|force|kill|terminate)'

# specialist_handoff_menu 検出キーワード
_SPECIALIST_KEYWORDS_RE='(specialist|PASS|NEEDS_WORK|Phase 3|Phase 4)'

# per-window inject 試行カウント（呼び出し元スコープの連想配列）
# 注: source 後に declare -A で初期化すること。サブシェルからは継承不可。
if [[ "$(declare -p _AUTO_INJECT_CYCLE_COUNT 2>/dev/null)" != "declare -A"* ]]; then
    declare -gA _AUTO_INJECT_CYCLE_COUNT 2>/dev/null || declare -A _AUTO_INJECT_CYCLE_COUNT 2>/dev/null || true
fi

# ===========================================================================
# _is_deny <text>
# deny-pattern に該当する場合 0、しない場合 1（grep 終了コード準拠）
# ===========================================================================
_is_deny() {
    echo "$1" | grep -iqE "$_DENY_RE"
}

# ===========================================================================
# _parse_menu_options <pane_content>
# menu option 行を stdout に出力する
# ===========================================================================
_parse_menu_options() {
    echo "$1" | grep -E "$_MENU_OPT_RE" || true
}

# ===========================================================================
# _extract_number <line>
# "  1. Foo" → "1" / "❯ 2. Bar" → "2"
# ===========================================================================
_extract_number() {
    echo "$1" | sed -E 's/^[[:space:]❯►▶→]*([1-9][0-9]*)[.):].*/\1/'
}

# ===========================================================================
# _is_cursor_line <line>
# cursor marker（❯ / ► / ▶ / →）を含む行なら 0、しない場合 1
# ===========================================================================
_is_cursor_line() {
    echo "$1" | grep -qE '^[[:space:]]*(❯|►|▶|→)'
}

# ===========================================================================
# auto_inject_menu <window> <pane_content> [thinking=<indicator>]
# ===========================================================================
auto_inject_menu() {
    local window="$1"
    local pane_content="$2"
    local thinking_arg="${3:-}"
    local thinking=""
    [[ "$thinking_arg" == thinking=* ]] && thinking="${thinking_arg#thinking=}"

    # 1. opt-in guard
    if [[ "${OBSERVER_AUTO_INJECT_ENABLE:-}" != "1" ]]; then
        return 0
    fi

    # 2. A2 thinking guard
    if [[ -n "$thinking" ]]; then
        return 0
    fi

    # 3. permission prompt guard（二重ガード）
    if echo "$pane_content" | grep -qE '^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)'; then
        return 0
    fi

    # 4. per-window cycle 制限（ファイルベース: サブシェルでも動作）
    # 厳密な排他は flock 内の二重チェックで保証する（TOCTOU 対策）
    local cycle_dir="${TMPDIR:-/tmp}"
    local window_safe
    window_safe=$(echo "$window" | LC_ALL=C tr -c '[:alnum:]-_' '_')
    local cycle_file="${cycle_dir}/cld-auto-inject-cycle-${window_safe}"
    local count=0
    if [[ -f "$cycle_file" ]]; then
        count=$(cat "$cycle_file" 2>/dev/null || echo 0)
        if [[ ! "$count" =~ ^[0-9]+$ ]]; then count=0; fi
    fi
    if [[ "$count" -ge 1 ]]; then
        echo "auto_inject_menu: skip (window=$window, cycle limit reached)" >&2
        return 0
    fi

    # 5. menu options 解析
    local options
    options=$(_parse_menu_options "$pane_content")
    if [[ -z "$options" ]]; then
        return 0
    fi

    # 6. 選択肢決定ロジック
    local selected_num="" selected_text="" menu_pattern="numbered_list"
    local skip_reason="" deny_matched=false

    # 6a. specialist_handoff_menu 検出（最優先）
    if echo "$pane_content" | grep -qE "$_SPECIALIST_KEYWORDS_RE" && \
       echo "$pane_content" | grep -qE '\[D\]'; then
        menu_pattern="specialist_handoff_menu"
        local d_line
        d_line=$(echo "$options" | grep -E '\[D\]' | head -1 || true)
        if [[ -n "$d_line" ]]; then
            selected_num=$(_extract_number "$d_line")
            selected_text="$d_line"
        fi
    fi

    # 6b. cursor marker 優先（specialist でない場合）
    if [[ -z "$selected_num" ]]; then
        local cursor_line=""
        while IFS= read -r line; do
            if _is_cursor_line "$line"; then
                cursor_line="$line"
                break
            fi
        done <<< "$options"

        if [[ -n "$cursor_line" ]]; then
            menu_pattern="cursor_marker"
            if ! _is_deny "$cursor_line"; then
                selected_num=$(_extract_number "$cursor_line")
                selected_text="$cursor_line"
            fi
            # cursor が deny → minimum-number に fallback（selected_num = "" のまま）
        fi
    fi

    # 6c. minimum-number fallback
    if [[ -z "$selected_num" ]]; then
        while IFS= read -r line; do
            if ! _is_deny "$line"; then
                selected_num=$(_extract_number "$line")
                selected_text="$line"
                break
            fi
        done <<< "$options"
    fi

    # 6d. 全選択肢 deny → skip + warning
    if [[ -z "$selected_num" ]]; then
        deny_matched=true
        skip_reason="all_deny"
        echo "auto_inject_menu: all options matched deny-pattern, skip inject (window=$window)" >&2
        _write_audit_trail "$window" "$menu_pattern" "" "" "true" "$skip_reason"
        return 0
    fi

    # 6e. selected_num を数字バリデーション（injection 防止）
    if [[ ! "$selected_num" =~ ^[1-9][0-9]*$ ]]; then
        echo "auto_inject_menu: selected_num validation failed: '$selected_num' (window=$window)" >&2
        return 0
    fi

    # 7. flock 排他制御（cycle read/write も保護範囲に含める）
    local lock_file="${TMPDIR:-/tmp}/cld-auto-inject-${window_safe}.lock"

    (
        flock -n 9 2>/dev/null || {
            echo "auto_inject_menu: lock acquire failed, skip (window=$window)" >&2
            exit 0
        }

        # cycle 二重チェック（TOCTOU 対策: flock 内で再確認）
        local flock_count=0
        [[ -f "$cycle_file" ]] && flock_count=$(cat "$cycle_file" 2>/dev/null || echo 0)
        if [[ ! "$flock_count" =~ ^[0-9]+$ ]]; then flock_count=0; fi
        if [[ "$flock_count" -ge 1 ]]; then
            exit 0
        fi

        # 8. inject 実行（単一 send-keys call で数字 + Enter を送信）
        tmux send-keys -t "$window" "$selected_num" Enter 2>/dev/null

        # 9. Press up 状態検知 → 追加 Enter
        sleep 0.3
        current_pane=$(tmux capture-pane -t "$window" -p 2>/dev/null | tail -5 || true)
        if echo "$current_pane" | grep -qF 'Press up to edit queued messages'; then
            tmux send-keys -t "$window" "" Enter 2>/dev/null
        fi

        # 10. cycle カウンタ更新（flock 保護範囲内）
        echo "$(( flock_count + 1 ))" > "$cycle_file" 2>/dev/null || true

    ) 9>"$lock_file"

    # 11. audit trail
    _write_audit_trail "$window" "$menu_pattern" "$selected_num" "$selected_text" "false" ""

    return 0
}

# ===========================================================================
# _write_audit_trail <window> <menu_pattern> <selected_option> <selected_text>
#                    <deny_matched> <skip_reason>
# ===========================================================================
_write_audit_trail() {
    local window="$1"
    local menu_pattern="$2"
    local selected_option="${3:-}"
    local selected_text="${4:-}"
    local deny_matched="${5:-false}"
    local skip_reason="${6:-}"

    local audit_dir="${AUTO_INJECT_AUDIT_DIR:-}"
    if [[ -z "$audit_dir" ]]; then
        audit_dir="${SUPERVISOR_EVENTS_DIR:-.supervisor/events}"
    fi
    mkdir -p "$audit_dir" 2>/dev/null || return 0

    local window_safe
    window_safe=$(echo "$window" | LC_ALL=C tr -c '[:alnum:]-_' '_')
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local fname="${audit_dir}/auto-inject-${window_safe}-${ts//:/}.json"

    local session_id=""
    session_id=$(jq -r '.session_id // empty' ".supervisor/session.json" 2>/dev/null || true)

    local safe_mode=false
    [[ "${OBSERVER_AUTO_INJECT_ENABLE:-}" == "1" ]] || safe_mode=true

    jq -nc \
        --arg window "$window" \
        --arg timestamp "$ts" \
        --arg menu_pattern "$menu_pattern" \
        --arg selected_option "$selected_option" \
        --arg selected_text "$selected_text" \
        --argjson deny_pattern_matched "$deny_matched" \
        --argjson safe_mode "$safe_mode" \
        --arg trigger_event "MENU-READY" \
        --arg session_id "${session_id:-}" \
        --arg skip_reason "${skip_reason:-}" \
        '{
          window: $window,
          timestamp: $timestamp,
          menu_pattern: $menu_pattern,
          selected_option: $selected_option,
          selected_text: $selected_text,
          deny_pattern_matched: $deny_pattern_matched,
          skip_reason: (if $skip_reason == "" then null else $skip_reason end),
          safe_mode: $safe_mode,
          trigger_event: $trigger_event,
          session_id: $session_id
        }' > "$fname" 2>/dev/null || true
}

# ===========================================================================
# auto_inject_reset_cycle <window>
# メインループが次サイクルに入る前に cycle ファイルを削除してリセットする
# ===========================================================================
auto_inject_reset_cycle() {
    local window="$1"
    local window_safe
    window_safe=$(echo "$window" | LC_ALL=C tr -c '[:alnum:]-_' '_')
    rm -f "${TMPDIR:-/tmp}/cld-auto-inject-cycle-${window_safe}" 2>/dev/null || true
}
