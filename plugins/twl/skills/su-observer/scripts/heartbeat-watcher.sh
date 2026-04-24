#!/usr/bin/env bash
# heartbeat-watcher.sh: Pilot heartbeat ファイルの 5 分 silence を監視して自動 capture-pane
#
# 背景（Issue #948, R4）:
#   supervisor-heartbeat.sh (PostToolUse hook) は Write/Edit 時に
#   .supervisor/events/heartbeat-<session_id> を書き出すが、
#   observer 側でこの mtime を監視する helper が存在しなかった。
#   本スクリプトはその片側実装を完成させる。
#
# 使用方法:
#   PILOT_WINDOW=wt-co-autopilot-102740 scripts/heartbeat-watcher.sh &
#
# 環境変数:
#   PILOT_WINDOW (MUST): 監視する Pilot tmux window 名
#   SILENCE_THRESHOLD_SEC (default: 300): 無音閾値（秒）
#   EVENTS_DIR (default: .supervisor/events): heartbeat ファイルディレクトリ
#   CAPTURE_OUTPUT_DIR (default: .supervisor/captures): capture-pane 出力ディレクトリ
#   POLL_INTERVAL_SEC (default: 60): ポーリング間隔（秒）

set -euo pipefail

PILOT_WINDOW="${PILOT_WINDOW:-}"
SILENCE_THRESHOLD_SEC="${SILENCE_THRESHOLD_SEC:-300}"
EVENTS_DIR="${EVENTS_DIR:-.supervisor/events}"
CAPTURE_OUTPUT_DIR="${CAPTURE_OUTPUT_DIR:-.supervisor/captures}"
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-60}"

if [[ -z "$PILOT_WINDOW" ]]; then
  echo "[heartbeat-watcher] ERROR: PILOT_WINDOW が未設定" >&2
  exit 1
fi

mkdir -p "$CAPTURE_OUTPUT_DIR"

_get_heartbeat_age() {
  local now
  now=$(date +%s)
  local latest_mtime=0
  local latest_file=""

  for hb_file in "${EVENTS_DIR}"/heartbeat-*; do
    [[ -f "$hb_file" ]] || continue
    local mtime
    mtime=$(stat -c %Y "$hb_file" 2>/dev/null || echo "0")
    if [[ "$mtime" -gt "$latest_mtime" ]]; then
      latest_mtime=$mtime
      latest_file=$hb_file
    fi
  done

  if [[ "$latest_mtime" -eq 0 ]]; then
    echo "-1"  # heartbeat ファイル不在
    return 0
  fi

  echo $(( now - latest_mtime ))
}

_do_capture() {
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local capture_file="${CAPTURE_OUTPUT_DIR}/capture-${PILOT_WINDOW}-${timestamp}.log"

  tmux capture-pane -t "$PILOT_WINDOW" -p -S -200 > "$capture_file" 2>/dev/null || {
    echo "[heartbeat-watcher] WARN: tmux capture-pane 失敗（window=$PILOT_WINDOW）" >&2
    return 1
  }
  echo "[heartbeat-watcher] CAPTURE: ${SILENCE_THRESHOLD_SEC}秒 silence 検出 → ${capture_file} に保存"
}

echo "[heartbeat-watcher] 起動: PILOT_WINDOW=${PILOT_WINDOW} threshold=${SILENCE_THRESHOLD_SEC}s"

while true; do
  age=$(_get_heartbeat_age)

  if [[ "$age" -eq -1 ]]; then
    echo "[heartbeat-watcher] WARN: heartbeat ファイルが存在しません（${EVENTS_DIR}/heartbeat-*）" >&2
  elif [[ "$age" -ge "$SILENCE_THRESHOLD_SEC" ]]; then
    echo "[heartbeat-watcher] SILENCE: heartbeat が ${age}秒間更新されていません（閾値: ${SILENCE_THRESHOLD_SEC}s）"
    _do_capture || true
  fi

  sleep "$POLL_INTERVAL_SEC"
done
