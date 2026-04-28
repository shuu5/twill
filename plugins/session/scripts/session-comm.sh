#!/bin/bash
# =============================================================================
# session-comm.sh - Claude Code セッション間通信プリミティブ
#
# Usage:
#   session-comm.sh capture <window> [--lines N] [--raw]
#   session-comm.sh inject <window> <text> [--force] [--no-enter]
#   session-comm.sh inject-file <window> <file> [--force] [--no-enter] [--wait SECONDS] [--wait SECONDS]
#   session-comm.sh wait-ready <window> [--timeout N]
#
# Dependencies: session-state.sh (#277)
# =============================================================================
set -euo pipefail

# テスト時のみ SESSION_COMM_SCRIPT_DIR を許可（_TEST_MODE ガード必須）
if [[ -n "${_TEST_MODE:-}" ]] && [[ -n "${SESSION_COMM_SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$SESSION_COMM_SCRIPT_DIR"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
MAX_INJECT_LEN=4096
DEFAULT_CAPTURE_LINES=50
DEFAULT_TIMEOUT=30

# =============================================================================
# ユーティリティ
# =============================================================================
usage() {
    cat <<'EOF'
Usage:
  session-comm.sh capture <window> [--lines N] [--all] [--raw]
  session-comm.sh inject <window> <text> [--force] [--no-enter]
  session-comm.sh inject-file <window> <file> [--force] [--no-enter] [--wait SECONDS]
  session-comm.sh wait-ready <window> [--timeout SECONDS]

Subcommands:
  capture      Capture pane content (ANSI stripped by default)
               --all   Capture full scrollback (mutually exclusive with --lines)
  inject       Send single-line text to a window (state-checked)
  inject-file  Send file content to a window via tmux load-buffer (multi-line safe)
               --wait SECONDS  Wait for input-waiting state before injecting
  wait-ready   Wait until window is input-waiting
EOF
    exit 1
}

# ウィンドウのtmuxターゲットを解決
resolve_target() {
    local window_name="$1"
    if [[ "$window_name" == *:* ]]; then
        if ! [[ "$window_name" =~ ^[A-Za-z0-9_./-]+:[0-9]+$ ]]; then
            echo "Error: invalid target format '$window_name'" >&2
            return 1
        fi
        if ! tmux has-session -t "${window_name%%:*}" 2>/dev/null; then
            echo "Error: session '${window_name%%:*}' not found" >&2
            return 1
        fi
        echo "$window_name"
        return
    fi
    local target
    target=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}' 2>/dev/null \
        | awk -v name="$window_name" '$2 == name { print $1; exit }')
    if [[ -z "$target" ]]; then
        echo "Error: window '$window_name' not found" >&2
        return 1
    fi
    echo "$target"
}

# ANSI エスケープコード除去
strip_ansi() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b(B//g'
}

# 制御文字サニタイズ（タブ以外の 0x00-0x1F を除去。改行・CRも除去: 単一行入力のみ）
sanitize_text() {
    tr -d '\000-\010\012-\015\016-\037'
}

# =============================================================================
# サブコマンド: capture
# =============================================================================
cmd_capture() {
    local window_name=""
    local lines=$DEFAULT_CAPTURE_LINES
    local lines_set=false
    local raw=false
    local all=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lines)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --lines requires a value" >&2
                    exit 1
                fi
                lines="$2"
                lines_set=true
                if ! [[ "$lines" =~ ^[0-9]+$ ]] || [[ "$lines" -eq 0 ]]; then
                    echo "Error: --lines requires a positive integer" >&2
                    exit 1
                fi
                shift 2
                ;;
            --all)
                all=true
                shift
                ;;
            --raw)
                raw=true
                shift
                ;;
            -*)
                echo "Error: unknown option '$1'" >&2
                usage
                ;;
            *)
                if [[ -z "$window_name" ]]; then
                    window_name="$1"
                else
                    echo "Error: unexpected argument '$1'" >&2
                    usage
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$window_name" ]]; then
        echo "Error: window name required" >&2
        usage
    fi

    # --all と --lines は排他
    if $all && $lines_set; then
        echo "Error: --all and --lines are mutually exclusive" >&2
        exit 1
    fi

    local target
    target=$(resolve_target "$window_name") || exit 1

    local captured
    if $all; then
        captured=$(tmux capture-pane -p -t "$target" -S - 2>/dev/null) || {
            echo "Error: failed to capture pane for '$window_name'" >&2
            exit 1
        }
    else
        captured=$(tmux capture-pane -p -t "$target" -S "-${lines}" 2>/dev/null) || {
            echo "Error: failed to capture pane for '$window_name'" >&2
            exit 1
        }
    fi

    if $raw; then
        printf '%s\n' "$captured"
    else
        printf '%s\n' "$captured" | strip_ansi
    fi
}

# =============================================================================
# サブコマンド: inject
# =============================================================================
cmd_inject() {
    local window_name=""
    local text=""
    local force=false
    local no_enter=false

    # 最初の2つの位置引数を取得
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --no-enter)
                no_enter=true
                shift
                ;;
            -*)
                echo "Error: unknown option '$1'" >&2
                usage
                ;;
            *)
                if [[ -z "$window_name" ]]; then
                    window_name="$1"
                elif [[ -z "$text" ]]; then
                    text="$1"
                else
                    echo "Error: unexpected argument '$1'" >&2
                    usage
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$window_name" ]]; then
        echo "Error: window name required" >&2
        usage
    fi
    if [[ -z "$text" ]]; then
        echo "Error: text required" >&2
        usage
    fi

    # サニタイズ
    text=$(printf '%s' "$text" | sanitize_text)

    # 最大長チェック
    if [[ ${#text} -gt $MAX_INJECT_LEN ]]; then
        echo "Error: text exceeds maximum length of ${MAX_INJECT_LEN} bytes" >&2
        exit 1
    fi

    local target
    target=$(resolve_target "$window_name") || exit 1

    # 状態チェック + retry（AC2: non-input-waiting 時は 5 秒後に retry）
    local max_retry_count=1
    local retry_count=0
    local state
    while true; do
        if ! state=$("$SCRIPT_DIR/session-state.sh" state "$window_name" 2>/dev/null); then
            echo "Warning: session-state.sh failed for '$window_name'" >&2
            state="unknown"
        fi

        if [[ "$state" == "input-waiting" ]]; then
            break
        fi

        if $force; then
            echo "Warning: target '$window_name' is in state '$state' (not input-waiting), sending anyway" >&2
            break
        fi

        if [[ "$retry_count" -ge "$max_retry_count" ]]; then
            echo "Error: target '$window_name' is in state '$state' (expected: input-waiting)" >&2
            exit 2
        fi

        sleep "${SESSION_COMM_RETRY_DELAY:-5}"  # AC2: 5 秒待機後に retry
        ((retry_count++)) || true
    done

    # flock で排他制御（AC1: 同一 pane への並列送信を直列化）
    local lock_file="${SESSION_COMM_LOCK_DIR:-/tmp}/session-comm-${target//[^a-zA-Z0-9]/-}.lock"
    {
        flock -w 30 9 || {
            echo "Error: failed to acquire send lock for '$window_name'" >&2
            exit 1
        }
        # send-keys で送信（-l: literal モード、キー名解釈を抑制）
        tmux send-keys -t "$target" -l "$text" || {
            echo "Error: failed to send keys to '$window_name'" >&2
            exit 1
        }

        if ! $no_enter; then
            tmux send-keys -t "$target" Enter
        fi
    } 9>"$lock_file"
}

# =============================================================================
# サブコマンド: inject-file
# =============================================================================
cmd_inject_file() {
    local window_name=""
    local file_path=""
    local force=false
    local no_enter=false
    local wait_timeout=0  # 0 = 待機なし（単発チェック）

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --no-enter)
                no_enter=true
                shift
                ;;
            --wait)
                wait_timeout="${2:-10}"
                if ! [[ "$wait_timeout" =~ ^[1-9][0-9]*$ ]]; then
                    echo "Error: --wait requires a positive integer" >&2
                    exit 1
                fi
                shift 2
                ;;
            -*)
                echo "Error: unknown option '$1'" >&2
                usage
                ;;
            *)
                if [[ -z "$window_name" ]]; then
                    window_name="$1"
                elif [[ -z "$file_path" ]]; then
                    file_path="$1"
                else
                    echo "Error: unexpected argument '$1'" >&2
                    usage
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$window_name" ]]; then
        echo "Error: window name required" >&2
        usage
    fi
    if [[ -z "$file_path" ]]; then
        echo "Error: file path required" >&2
        usage
    fi
    if [[ ! -f "$file_path" ]]; then
        echo "Error: file not found: $file_path" >&2
        exit 1
    fi

    local target
    target=$(resolve_target "$window_name") || exit 1

    # 状態チェック: --wait 指定時は input-waiting までアクティブ待機
    if [[ "$wait_timeout" -gt 0 ]]; then
        if ! "$SCRIPT_DIR/session-state.sh" wait "$window_name" input-waiting --timeout "$wait_timeout"; then
            echo "Error: target '$window_name' did not reach input-waiting within ${wait_timeout}s" >&2
            exit 2
        fi
    else
        local state
        if ! state=$("$SCRIPT_DIR/session-state.sh" state "$window_name" 2>/dev/null); then
            echo "Warning: session-state.sh failed for '$window_name'" >&2
            state="unknown"
        fi

        if [[ "$state" != "input-waiting" ]]; then
            if $force; then
                echo "Warning: target '$window_name' is in state '$state' (not input-waiting), sending anyway" >&2
            else
                echo "Error: target '$window_name' is in state '$state' (expected: input-waiting)" >&2
                exit 2
            fi
        fi
    fi

    # tmux load-buffer + paste-buffer で改行を含むテキストを安全に送達
    tmux load-buffer "$file_path" || {
        echo "Error: failed to load buffer from '$file_path'" >&2
        exit 1
    }

    # tmux >= 3.2 では -p フラグで bracketed paste mode を有効化
    local tmux_major tmux_minor
    tmux_major=$(tmux -V | sed 's/tmux \([0-9]*\)\..*/\1/')
    tmux_minor=$(tmux -V | sed 's/tmux [0-9]*\.\([0-9]*\).*/\1/')
    if [[ "$tmux_major" -gt 3 ]] || { [[ "$tmux_major" -eq 3 ]] && [[ "$tmux_minor" -ge 2 ]]; }; then
        tmux paste-buffer -p -t "$target" || {
            echo "Error: failed to paste buffer to '$window_name'" >&2
            exit 1
        }
    else
        tmux paste-buffer -t "$target" || {
            echo "Error: failed to paste buffer to '$window_name'" >&2
            exit 1
        }
    fi

    if ! $no_enter; then
        # paste-buffer 後に待機（Ink の非同期イベントループがペースト処理を
        # 完了する前に Enter が到着するタイミング問題を回避。#234）
        sleep 0.3
        tmux send-keys -t "$target" Enter
    fi
}

# =============================================================================
# サブコマンド: wait-ready
# =============================================================================
cmd_wait_ready() {
    local window_name=""
    local timeout=$DEFAULT_TIMEOUT

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --timeout requires a value" >&2
                    exit 1
                fi
                timeout="$2"
                if ! [[ "$timeout" =~ ^[1-9][0-9]*$ ]]; then
                    echo "Error: --timeout requires a positive integer" >&2
                    usage
                fi
                shift 2
                ;;
            -*)
                echo "Error: unknown option '$1'" >&2
                usage
                ;;
            *)
                if [[ -z "$window_name" ]]; then
                    window_name="$1"
                else
                    echo "Error: unexpected argument '$1'" >&2
                    usage
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$window_name" ]]; then
        echo "Error: window name required" >&2
        usage
    fi

    exec "$SCRIPT_DIR/session-state.sh" wait "$window_name" input-waiting --timeout "$timeout"
}

# =============================================================================
# メインディスパッチ
# =============================================================================
case "${1:-}" in
    capture)
        shift
        cmd_capture "$@"
        ;;
    inject)
        shift
        cmd_inject "$@"
        ;;
    inject-file)
        shift
        cmd_inject_file "$@"
        ;;
    wait-ready)
        shift
        cmd_wait_ready "$@"
        ;;
    -h|--help|"")
        usage
        ;;
    *)
        echo "Error: unknown subcommand '$1'" >&2
        usage
        ;;
esac
