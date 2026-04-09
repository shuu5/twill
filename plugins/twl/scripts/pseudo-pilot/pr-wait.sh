#!/usr/bin/env bash
# pr-wait.sh - PR 作成を polling で待機
# Usage: pr-wait.sh <branch> [--timeout SECONDS] [--interval SECONDS]
#
# Exit codes:
#   0 = PR 検出成功
#   1 = timeout
#   2 = 依存エラー or 引数エラー
set -euo pipefail

# --- dependency check ---
if ! command -v gh &>/dev/null; then
    echo "[pr-wait] error: 'gh' CLI が見つかりません。インストール後に再実行してください。" >&2
    exit 2
fi

# --- argument parsing ---
BRANCH="${1:?Usage: pr-wait.sh <branch> [--timeout SECONDS] [--interval SECONDS]}"
shift || true

TIMEOUT=1800
INTERVAL=10

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
            echo "[pr-wait] error: 不明な引数: $1" >&2
            exit 2
            ;;
    esac
done

# --- polling loop ---
START=$(date +%s)
while true; do
    PR_NUM=$(gh pr view "$BRANCH" --json number -q .number 2>/dev/null || echo "")
    if [[ -n "$PR_NUM" ]]; then
        echo "$PR_NUM"
        exit 0
    fi
    NOW=$(date +%s)
    if (( NOW - START >= TIMEOUT )); then
        echo "[pr-wait] timeout after ${TIMEOUT}s" >&2
        exit 1
    fi
    sleep "$INTERVAL"
done
