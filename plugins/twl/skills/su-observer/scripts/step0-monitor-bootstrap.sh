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

# OBSERVER_DAEMON_HEARTBEAT_STALE_SEC: heartbeat.json の staleness 判定閾値（秒）
# cld-observe-any 側の HEARTBEAT_INTERVAL_SEC（60 秒）とは独立して読み取り側で定義する（pitfalls §11.1）
OBSERVER_DAEMON_HEARTBEAT_STALE_SEC="${OBSERVER_DAEMON_HEARTBEAT_STALE_SEC:-120}"
if [[ ! "$OBSERVER_DAEMON_HEARTBEAT_STALE_SEC" =~ ^[0-9]+$ ]]; then
  echo "ERROR: OBSERVER_DAEMON_HEARTBEAT_STALE_SEC は非負整数である必要があります: $OBSERVER_DAEMON_HEARTBEAT_STALE_SEC" >&2
  exit 2
fi

_daemon_running() {
  local hb_file="${SUPERVISOR_DIR}/observer-daemon-heartbeat.json"

  # (a) pgrep -f cld-observe-any → false なら grace period チェックへ
  local pgrep_pids pgrep_exit=0
  pgrep_pids=$(pgrep -f "cld-observe-any" 2>/dev/null) || pgrep_exit=1

  # (b) heartbeat.json 不在 → grace period: pgrep 結果を返却（既存挙動互換）+ stderr WARNING
  # 新規インストール / CI / #1154 migration 期間の互換性のためフォールバック
  if [[ ! -f "$hb_file" ]]; then
    echo "WARNING: ${hb_file} が不在です。pgrep 単独判定（grace period）で継続します" >&2
    return $pgrep_exit
  fi

  # heartbeat.json が存在する場合は (a) pgrep が false なら即 false 返却
  [[ $pgrep_exit -eq 0 ]] || return 1

  # (c) heartbeat.json mtime ≤ OBSERVER_DAEMON_HEARTBEAT_STALE_SEC 秒
  # TOCTOU window（既知トレードオフ）: pgrep (a) 後に daemon 死亡で最大 STALE_SEC の偽陽性あり
  local mtime_age
  mtime_age=$(( $(date +%s) - $(stat -c %Y "$hb_file" 2>/dev/null || echo 0) ))
  if (( mtime_age > OBSERVER_DAEMON_HEARTBEAT_STALE_SEC )); then
    return 1
  fi

  # (d) JSON 内の writer == "cld-observe-any" かつ pid が pgrep 結果に含まれる
  # || true: grep no-match (exit 1) が set -euo pipefail 下でスクリプトを exit させないよう抑制
  local hb_writer hb_pid
  hb_writer=$(grep -o '"writer":"[^"]*"' "$hb_file" 2>/dev/null | cut -d'"' -f4 || true)
  hb_pid=$(grep -o '"pid":[0-9]*' "$hb_file" 2>/dev/null | grep -o '[0-9]*$' || true)

  [[ "$hb_writer" == "cld-observe-any" ]] || return 1
  [[ -n "$hb_pid" ]] || return 1
  echo "$pgrep_pids" | grep -qw "$hb_pid" || return 1

  return 0
}

_emit_start_commands() {
  echo "# Monitor task 起動コマンド (起動時 SOP 用)"
  echo "# cld-observe-any daemon + Monitor tool tail -F 連携起動"
  echo ""
  echo "# env: IDLE_COMPLETED_AUTO_KILL=1 を monitor セッションに恒久設定"
  echo "export IDLE_COMPLETED_AUTO_KILL=1"
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
