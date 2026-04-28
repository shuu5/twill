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
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
# stagnate-suppress-check.sh パス解決 (#1052)
_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STAGNATE_SUPPRESS_CHECK="${STAGNATE_SUPPRESS_CHECK:-${_SCRIPT_DIR}/../../../scripts/stagnate-suppress-check.sh}"

if [[ -z "$PILOT_WINDOW" ]]; then
  echo "[heartbeat-watcher] ERROR: PILOT_WINDOW が未設定" >&2
  exit 1
fi

# PILOT_WINDOW をファイルパスに使うため英数字・ハイフン・アンダースコアのみ許可
if [[ ! "$PILOT_WINDOW" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "[heartbeat-watcher] ERROR: PILOT_WINDOW に無効な文字が含まれています: ${PILOT_WINDOW}" >&2
  exit 1
fi

mkdir -p "$CAPTURE_OUTPUT_DIR"

_get_heartbeat_age() {
  local now hb_file mtime
  now=$(date +%s)
  local latest_mtime=0
  local latest_file=""

  for hb_file in "${EVENTS_DIR}"/heartbeat-*; do
    [[ -f "$hb_file" ]] || continue
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

# 自己 PID を watcher-pid-heartbeat に記録 — context-budget-monitor.sh が参照して kill する (#1052)
_HEARTBEAT_PID_FILE="${SUPERVISOR_DIR}/watcher-pid-heartbeat"
echo $$ > "$_HEARTBEAT_PID_FILE" 2>/dev/null || true
trap 'rm -f "$_HEARTBEAT_PID_FILE" 2>/dev/null || true' EXIT

while true; do
  age=$(_get_heartbeat_age)
  age="${age:-0}"  # empty guard (_get_heartbeat_age が空文字を返した場合の安全策)

  if [[ "$age" -eq -1 ]]; then
    echo "[heartbeat-watcher] WARN: heartbeat ファイルが存在しません（${EVENTS_DIR}/heartbeat-*）" >&2
  elif [[ "$age" -ge "$SILENCE_THRESHOLD_SEC" ]]; then
    # STAGNATE suppress 条件チェック (#1052)
    # [PHASE-COMPLETE] / 実装完了 / session completed/archived / session-end ファイルで suppress
    _latest_capture=$(ls -t "${CAPTURE_OUTPUT_DIR}/capture-${PILOT_WINDOW}-"*.log 2>/dev/null | head -1 || echo "")
    _session_json="${AUTOPILOT_DIR}/session.json"
    if [[ -x "$STAGNATE_SUPPRESS_CHECK" ]] && \
       bash "$STAGNATE_SUPPRESS_CHECK" \
         ${_latest_capture:+--capture-file "$_latest_capture"} \
         --session-json "$_session_json" \
         --events-dir "$EVENTS_DIR" 2>/dev/null; then
      echo "[heartbeat-watcher] STAGNATE suppress: 完了条件を検出、emit スキップ"
    else
      echo "[heartbeat-watcher] SILENCE: heartbeat が ${age}秒間更新されていません（閾値: ${SILENCE_THRESHOLD_SEC}s）"
      _do_capture || true
    fi
  fi

  sleep "$POLL_INTERVAL_SEC"
done
