#!/usr/bin/env bash
# step0-monitor-bootstrap.sh: Monitor task 起動コマンドを stdout に emit する
# Purpose: Step 0 step 6.5 から呼び出し、cld-observe-any daemon + Monitor tool tail -F の
#          連携起動コマンドを stdout に emit する（state file 書き込みなし）
# Environment:
#   SUPERVISOR_DIR  (default: .supervisor)  : ログファイル出力先
# Modes:
#   (default / --check)  exit 0=daemon 起動済み, exit 1=未起動
#   --write              (noop: 互換用、ambient パターン踏襲)
# AC2.2: 定期 audit 用 polling patterns:
#   Enter to select / ^❯ [1-9]. / Press up to edit queued
#   (tmux capture-pane -p | sed 's/\x1b\[[0-9;]*m//g' | grep -E で使用)

set -euo pipefail

SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
# パス検証: 英数字・ドット・アンダースコア・ハイフン・スラッシュのみ許可（特殊文字・空白・.. 拒否）
if [[ ! "$SUPERVISOR_DIR" =~ ^[a-zA-Z0-9./_-]+$ ]] || [[ "$SUPERVISOR_DIR" == *..* ]]; then
  echo "ERROR: SUPERVISOR_DIR に無効な文字が含まれています: $SUPERVISOR_DIR" >&2
  exit 2
fi
LOG_FILE="${SUPERVISOR_DIR}/cld-observe-any.log"
MODE="${1:-}"

_daemon_running() {
  pgrep -f "cld-observe-any" > /dev/null 2>&1
}

_emit_start_commands() {
  echo "# Monitor task 起動コマンド (起動時 SOP 用)"
  echo "# cld-observe-any daemon + Monitor tool tail -F 連携起動"
  echo ""
  echo "# Step 1: cld-observe-any daemon を logfile redirect で起動"
  echo "mkdir -p ${SUPERVISOR_DIR}"
  echo "plugins/session/scripts/cld-observe-any \\"
  echo "  --pattern '^(ap-|wt-|coi-|coe-)' \\"
  echo "  2>&1 | tee -a ${LOG_FILE} &"
  echo ""
  echo "# Step 2: logfile が出力開始するまで待機"
  echo "until [[ -s ${LOG_FILE} ]]; do sleep 1; done"
  echo ""
  echo "# Step 3: Monitor tool で tail -F 監視"
  echo "tail -F ${LOG_FILE}"
  echo ""
  echo "# 定期 audit pattern (5 分ごとに全 controller window に対し実行):"
  echo "# tmux capture-pane -p | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Enter to select|^❯ [1-9]\.|Press up to edit queued'"
}

case "$MODE" in
  --check)
    if _daemon_running; then
      echo "RUNNING"
      exit 0
    else
      echo "NOT_RUNNING"
      exit 1
    fi
    ;;
  --write)
    # 互換用 noop（ambient パターン踏襲）
    exit 0
    ;;
  "")
    if _daemon_running; then
      echo "# cld-observe-any は既に起動中 (pgrep -f cld-observe-any: 既存 PID 検出)" >&2
      echo "# daemon 再起動をスキップします" >&2
    else
      _emit_start_commands
    fi
    ;;
  *)
    echo "Usage: $0 [--check|--write]" >&2
    exit 2
    ;;
esac
