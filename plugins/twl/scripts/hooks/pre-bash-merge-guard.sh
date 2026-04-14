#!/usr/bin/env bash
# PreToolUse hook: Worker からの gh pr merge 直接実行を防止 (#671)
#
# Claude Code の PreToolUse フェーズで呼び出される。
# $TOOL_INPUT_command に `gh pr merge` が含まれる場合、
# AUTOPILOT_DIR 設定時（= Worker セッション）のみブロックする。
#
# auto-merge.sh 経由の呼び出しは許可（auto-merge.sh 内のガードに委譲）。
#
# 不変条件 C: Worker は gh pr merge を直接実行してはならない。
#
# 終了コード:
#   0 — 通過
#   2 — ブロック

set -uo pipefail

cmd="${TOOL_INPUT_command:-}"

# コマンドが空 → no-op
[[ -z "$cmd" ]] && exit 0

# gh pr merge を含まない → no-op
echo "$cmd" | grep -qE '(^|[;&|]\s*)gh\s+pr\s+merge' || exit 0

# auto-merge.sh 経由 → 許可（auto-merge.sh 内のガードに委譲）
echo "$cmd" | grep -qE 'auto-merge\.sh' && exit 0

# AUTOPILOT_DIR 未設定 → 通常セッション、許可
[[ -z "${AUTOPILOT_DIR:-}" ]] && exit 0

# Worker セッションからの gh pr merge 直接実行 → ブロック
echo "不変条件C: Worker からの gh pr merge 直接実行は禁止。auto-merge.sh 経由で実行してください (#671)" >&2
exit 2
