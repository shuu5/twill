#!/usr/bin/env bash
# worker-done-wait.sh - Worker が input-waiting 状態になるまで polling で待機
# Usage: worker-done-wait.sh <window> [--timeout SECONDS] [--interval SECONDS]
#
# Exit codes:
#   0 = input-waiting 検出成功
#   1 = timeout
#   2 = 依存エラー or 引数エラー
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_STATE_SH="${SCRIPT_DIR}/../../session/scripts/session-state.sh"

# --- dependency check ---
if ! command -v tmux &>/dev/null; then
    echo "[worker-done-wait] error: 'tmux' が見つかりません。インストール後に再実行してください。" >&2
    exit 2
fi
if [[ ! -f "$SESSION_STATE_SH" ]]; then
    echo "[worker-done-wait] error: session-state.sh が見つかりません: $SESSION_STATE_SH" >&2
    exit 2
fi

# --- argument parsing ---
WINDOW="${1:?Usage: worker-done-wait.sh <window> [--timeout SECONDS] [--interval SECONDS]}"
shift || true

TIMEOUT=1800
INTERVAL=5

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            TIMEOUT="${2:?--timeout requires a value}"
            shift 2
            ;;
        --interval)
            INTERVAL="${2:?--interval requires a value}"
            shift 2
            ;;
        *)
            echo "[worker-done-wait] error: 不明な引数: $1" >&2
            exit 2
            ;;
    esac
done

# --- polling loop ---
START=$(date +%s)
while true; do
    STATE=$(bash "$SESSION_STATE_SH" state "$WINDOW" 2>/dev/null || echo "")
    if [[ "$STATE" == "input-waiting" ]]; then
        exit 0
    fi
    NOW=$(date +%s)
    if (( NOW - START >= TIMEOUT )); then
        echo "[worker-done-wait] timeout after ${TIMEOUT}s (last state: ${STATE:-unknown})" >&2
        exit 1
    fi
    sleep "$INTERVAL"
done
