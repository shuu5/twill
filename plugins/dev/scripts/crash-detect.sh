#!/usr/bin/env bash
# crash-detect.sh - Worker crash 検知（不変条件 G）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="$PROJECT_ROOT/.autopilot"
STATE_READ="$SCRIPT_DIR/state-read.sh"
STATE_WRITE="$SCRIPT_DIR/state-write.sh"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --issue N --window <window-name>

tmux ペインの存在を確認し、消失していれば crash として status を failed に遷移する。

Options:
  --issue N               Issue番号（必須）
  --window <window-name>  tmux ウィンドウ名（必須）
  -h, --help              このヘルプを表示

Exit codes:
  0: ペイン存在（正常） or status が running 以外（チェック不要）
  1: エラー
  2: crash 検知（status を failed に遷移済み）
EOF
}

issue=""
window=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) issue="$2"; shift 2 ;;
    --window) window="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$issue" || -z "$window" ]]; then
  echo "ERROR: --issue と --window は必須です" >&2
  exit 1
fi

# issue番号の数値バリデーション
if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --issue は正の整数を指定してください: $issue" >&2
  exit 1
fi

# 現在の status を取得
status=$("$STATE_READ" --type issue --issue "$issue" --field status)

# running 以外はチェック不要（merge-ready で終了は正常）
if [[ "$status" != "running" ]]; then
  exit 0
fi

# tmux ペイン存在チェック
if tmux list-panes -t "$window" &>/dev/null; then
  # ペイン存在 → 正常
  exit 0
fi

# ペイン消失 + status=running → crash 検知
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
current_step=$("$STATE_READ" --type issue --issue "$issue" --field current_step)

echo "CRASH: Worker crash を検知しました (Issue #$issue, window=$window)" >&2

# failure 情報を構築して status=failed に遷移
failure_json=$(jq -n \
  --arg message "Worker crash detected: tmux window '$window' disappeared" \
  --arg step "$current_step" \
  --arg timestamp "$now" \
  '{ message: $message, step: $step, timestamp: $timestamp }')

"$STATE_WRITE" --type issue --issue "$issue" --role pilot \
  --set "status=failed" \
  --set "failure=$failure_json"

exit 2
