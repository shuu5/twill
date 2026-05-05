#!/bin/bash
# session-comm-backend-mcp.sh — MCP mailbox backend for session_msg API (ADR-029 Decision 5)
#
# Calls twl_send_msg_handler (tools_comm.py) via Python for file-based jsonl mailbox.
# flock protection for atomic append is handled by the Python handler (ADR-028).
#
# Backend modes:
#   mcp              — MCP mailbox primary (Phase 3+ default)
#   mcp_with_fallback — tmux reliable delivery + MCP shadow logging (Phase 2)
#
# Source mode (from session-comm.sh):
#   source session-comm-backend-mcp.sh
#   _backend_mcp_send TARGET CONTENT [opts]
#   _backend_shadow_send TARGET CONTENT [opts]
#
# Direct execution:
#   session-comm-backend-mcp.sh {send|shadow-send} TARGET CONTENT [opts]

set -euo pipefail

_BACKEND_MCP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate twill root (up to 6 levels from plugins/session/scripts/)
_find_twill_root() {
    local dir="$1"
    local depth=0
    while [[ "$dir" != "/" && $depth -lt 6 ]]; do
        if [[ -d "${dir}/cli/twl/src" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
        ((depth++)) || true
    done
    return 1
}

_TWILL_ROOT="${_TWILL_ROOT:-$(_find_twill_root "$_BACKEND_MCP_SCRIPT_DIR" 2>/dev/null || echo "")}"

# _backend_mcp_python_send TARGET CONTENT TYPE
# Calls twl_send_msg_handler via Python (uses flock-based jsonl atomic append).
_backend_mcp_python_send() {
    local _mcp_target="$1"
    local _mcp_content="$2"
    local _mcp_type="${3:-message}"
    local _twill_root="${_TWILL_ROOT:-}"

    TWILL_MCP_TARGET="$_mcp_target" \
    TWILL_MCP_CONTENT="$_mcp_content" \
    TWILL_MCP_TYPE="$_mcp_type" \
    TWILL_ROOT="$_twill_root" \
    python3 - <<'PYEOF'
import sys, os, json

twill_root = os.environ.get('TWILL_ROOT', '')
target = os.environ.get('TWILL_MCP_TARGET', '')
type_ = os.environ.get('TWILL_MCP_TYPE', 'message')
content = os.environ.get('TWILL_MCP_CONTENT', '')

if twill_root:
    sys.path.insert(0, os.path.join(twill_root, 'cli/twl/src'))

try:
    from twl.mcp_server.tools_comm import twl_send_msg_handler
    result = twl_send_msg_handler(
        to=target,
        type_=type_,
        content=json.dumps({'text': content}),
    )
    print(result)
    sys.exit(0)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF
}

# _backend_mcp_send TARGET CONTENT [--enter-only] [--no-enter] [--type=TYPE]
_backend_mcp_send() {
    local target="${1:-}"
    local content="${2:-}"
    local enter_only=false
    local type="message"
    shift 2 2>/dev/null || { shift $# 2>/dev/null; true; }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enter-only) enter_only=true ;;
            --no-enter)   : ;;
            --type=*)     type="${1#--type=}" ;;
            *)            ;;
        esac
        shift
    done

    if [[ -z "$target" ]]; then
        echo "Error: backend-mcp send: target required" >&2
        return 1
    fi

    if $enter_only; then
        type="enter"
        content=""
    fi

    _backend_mcp_python_send "$target" "$content" "$type"
}

# _backend_shadow_send TARGET CONTENT [opts] — mcp_with_fallback mode
# Always sends via tmux (reliable delivery), also logs to MCP mailbox in background
# for Phase 2 shadow observation. mcp-shadow-compare.sh reads the shadow log.
_backend_shadow_send() {
    local target="${1:-}"
    local content="${2:-}"

    # Reliable delivery via tmux backend
    # shellcheck source=./session-comm-backend-tmux.sh
    source "${_BACKEND_MCP_SCRIPT_DIR}/session-comm-backend-tmux.sh"
    _backend_tmux_send "$@"
    local _tmux_exit=$?

    # Shadow log to MCP mailbox (background, non-blocking)
    local _shadow_log="${AUTOPILOT_DIR:-.autopilot}/mailbox/shadow-$(date +%Y%m%d).jsonl"
    {
        mkdir -p "$(dirname "$_shadow_log")" 2>/dev/null || true
        local _mcp_result="ok"
        _backend_mcp_python_send "$target" "$content" "shadow" 2>/dev/null \
            || _mcp_result="error"
        local _ts
        _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
        printf '{"ts":"%s","target":"%s","tmux_exit":%d,"mcp_result":"%s","fallback":true}\n' \
            "$_ts" "$target" "$_tmux_exit" "$_mcp_result" >> "$_shadow_log" 2>/dev/null || true
    } &

    return $_tmux_exit
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        send)        shift; _backend_mcp_send "$@" ;;
        shadow-send) shift; _backend_shadow_send "$@" ;;
        *)
            echo "Usage: session-comm-backend-mcp.sh {send|shadow-send} TARGET CONTENT [opts]" >&2
            exit 1
            ;;
    esac
fi
