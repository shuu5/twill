#!/usr/bin/env bash
# crash-detect.sh - Worker crash 検知（不変条件 G）
# session-state.sh 統合: 5状態検出（idle/input-waiting/processing/error/exited）
# フォールバック: session-state.sh 非存在時は従来の tmux list-panes ベース検知
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}"
# shellcheck source=./lib/python-env.sh
source "${SCRIPT_DIR}/lib/python-env.sh"

# session-state.sh の解決（環境変数で上書き可能）
SESSION_STATE_CMD="${SESSION_STATE_CMD-$HOME/ubuntu-note-system/scripts/session-state.sh}"
# パス安全性検証: 相対パス・空文字列・.. を含むパスを拒否
if [[ -n "$SESSION_STATE_CMD" && "$SESSION_STATE_CMD" == /* && "$SESSION_STATE_CMD" != *..* && -x "$SESSION_STATE_CMD" ]]; then
  USE_SESSION_STATE=true
else
  USE_SESSION_STATE=false
fi

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --issue N --window <window-name>

Worker の状態を確認し、異常状態であれば crash として status を failed に遷移する。
session-state.sh が利用可能な場合は 5 状態検出、不在時は tmux list-panes にフォールバック。

Options:
  --issue N               Issue番号（必須）
  --window <window-name>  tmux ウィンドウ名（必須）
  -h, --help              このヘルプを表示

Exit codes:
  0: Worker 正常稼働 or status が running 以外（チェック不要）
  1: エラー
  2: crash 検知（status を failed に遷移済み）
EOF
}

# --- crash 報告共通関数 ---
report_crash() {
  local issue="$1" window="$2" message="$3" detected_state="$4"
  local now current_step failure_json

  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  current_step=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field current_step)

  echo "CRASH: Worker crash を検知しました (Issue #$issue, window=$window, state=$detected_state)" >&2

  failure_json=$(jq -n \
    --arg message "$message" \
    --arg step "$current_step" \
    --arg timestamp "$now" \
    --arg detected_state "$detected_state" \
    '{ message: $message, step: $step, timestamp: $timestamp, detected_state: $detected_state }')

  python3 -m twl.autopilot.state write --type issue --issue "$issue" --role pilot \
    --set "status=failed" \
    --set "failure=$failure_json"
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

if [[ -z "$issue" ]]; then
  echo "ERROR: --issue は必須です" >&2
  exit 1
fi

# window が空の場合は no-op（resolve_worker_window が解決不能だったケース）
if [[ -z "$window" ]]; then
  echo "INFO: --window が未指定のため crash-detect をスキップします (issue=#${issue})" >&2
  exit 0
fi

# issue番号の数値バリデーション
if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --issue は正の整数を指定してください: $issue" >&2
  exit 1
fi

# 現在の status を取得
status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status)

# running 以外はチェック不要（merge-ready で終了は正常）
if [[ "$status" != "running" ]]; then
  exit 0
fi

# --- session-state.sh パス ---
if [[ "$USE_SESSION_STATE" == "true" ]]; then
  detected_state=$("$SESSION_STATE_CMD" state "$window" 2>/dev/null) || detected_state=""

  # session-state.sh 実行失敗 → フォールバック
  if [[ -z "$detected_state" ]]; then
    USE_SESSION_STATE=false
  else
    case "$detected_state" in
      processing|idle|input-waiting)
        # Worker 正常稼働
        exit 0
        ;;
      error)
        report_crash "$issue" "$window" \
          "Worker error detected via session-state: error" \
          "error"
        exit 2
        ;;
      exited)
        report_crash "$issue" "$window" \
          "Worker exited detected via session-state: exited" \
          "exited"
        exit 2
        ;;
      *)
        # 未知の状態 → フォールバック
        USE_SESSION_STATE=false
        ;;
    esac
  fi
fi

# --- フォールバック: tmux list-panes パス ---
if tmux list-panes -t "$window" &>/dev/null; then
  # ペイン存在 → 正常
  exit 0
fi

# ペイン消失 + status=running → crash 検知
report_crash "$issue" "$window" \
  "Worker crash detected: tmux window '$window' disappeared" \
  "pane_absent"

exit 2
