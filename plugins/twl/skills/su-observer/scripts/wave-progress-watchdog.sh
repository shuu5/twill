#!/usr/bin/env bash
# wave-progress-watchdog.sh — Wave PR 進行監視デーモン (#1429)
#
# 使用方法:
#   WAVE_PROGRESS_WATCHDOG_ENABLED=1 bash wave-progress-watchdog.sh
#
# 環境変数:
#   WAVE_PROGRESS_WATCHDOG_ENABLED  opt-in フラグ（デフォルト OFF）
#   SUPERVISOR_DIR                  supervisor ディレクトリ（デフォルト: .supervisor）
#   WAVE_QUEUE_FILE                 wave-queue.json パス（デフォルト: SUPERVISOR_DIR/wave-queue.json）
#   POLL_INTERVAL_SEC               polling 間隔（デフォルト: 30 秒）
#   AUTO_NEXT_SPAWN_SCRIPT          auto-next-spawn.sh パス
#   AUTOPILOT_DIR                   autopilot ディレクトリ（デフォルト: .autopilot）
#
# 動作:
#   .supervisor/events/wave-${current_wave}-pr-merged-*.json を polling 監視し、
#   current_wave の全 Issue が merged された時点で auto-next-spawn.sh を 1 回だけ呼び出す。
#   idempotency は completed-flag（.supervisor/locks/wave-N-completed.flag）で保証。
#
# lock / PID / cleanup:
#   lock: .supervisor/locks/wave-progress-watchdog.lock (flock -n)
#   PID:  .supervisor/watcher-pid-wave-progress
#   trap: SIGTERM/EXIT で PID ファイルを削除（context-budget-monitor.sh 互換）

set -uo pipefail

# ---- --help ----
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: WAVE_PROGRESS_WATCHDOG_ENABLED=1 bash wave-progress-watchdog.sh"
  echo "See refs/ref-wave-progress-watchdog.md for full documentation."
  exit 0
fi

# ---- AC-12: opt-in ガード（デフォルト OFF） ----
WAVE_PROGRESS_WATCHDOG_ENABLED="${WAVE_PROGRESS_WATCHDOG_ENABLED:-0}"
if [[ "$WAVE_PROGRESS_WATCHDOG_ENABLED" != "1" ]]; then
  echo "[wave-progress-watchdog] WAVE_PROGRESS_WATCHDOG_ENABLED is not 1 — exiting (default OFF)" >&2
  exit 0
fi

# ---- パス解決 ----
_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
WAVE_QUEUE_FILE="${WAVE_QUEUE_FILE:-${SUPERVISOR_DIR}/wave-queue.json}"
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-30}"
AUTO_NEXT_SPAWN_SCRIPT="${AUTO_NEXT_SPAWN_SCRIPT:-${_SCRIPT_DIR}/auto-next-spawn.sh}"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"

mkdir -p "${SUPERVISOR_DIR}/events" "${SUPERVISOR_DIR}/locks" 2>/dev/null || true

# ---- AC-6: PID ファイル（context-budget-monitor.sh 互換 watcher-pid-* プレフィックス） ----
_PID_FILE="${SUPERVISOR_DIR}/watcher-pid-wave-progress"
echo $$ > "$_PID_FILE" 2>/dev/null || true
trap 'rm -f "$_PID_FILE" 2>/dev/null || true' SIGTERM EXIT

# ---- AC-4: flock -n で二重 invocation skip ----
_LOCK_FILE="${SUPERVISOR_DIR}/locks/wave-progress-watchdog.lock"
exec 9>"$_LOCK_FILE"
if ! flock -n 9; then
  echo "[wave-progress-watchdog] INFO: already running (lock held) — skip" >&2
  exit 0
fi

# ---- ヘルパー関数 ----

_get_current_wave() {
  [[ ! -f "$WAVE_QUEUE_FILE" ]] && { echo ""; return 1; }
  jq -r '.current_wave // empty' "$WAVE_QUEUE_FILE" 2>/dev/null || echo ""
}

# AC-3: wave-queue.json.queue[].issues を .wave フィールドで current_wave フィルタして取得
_get_wave_issue_count() {
  local wave="$1"
  [[ ! -f "$WAVE_QUEUE_FILE" ]] && { echo "0"; return 1; }
  jq -r --argjson w "$wave" \
    '[.queue[] | select(.wave == $w) | .issues[]] | length' \
    "$WAVE_QUEUE_FILE" 2>/dev/null || echo "0"
}

_count_merged_events() {
  local wave="$1"
  local count=0
  local events_dir="${SUPERVISOR_DIR}/events"
  for f in "${events_dir}/wave-${wave}-pr-merged-"*.json; do
    [[ -f "$f" ]] && count=$(( count + 1 ))
  done
  echo "$count"
}

# AC-5: 全 Issue merged かどうかを判定（false positive 防止）
# 未完了（一部のみ merged）は spawn skip して次 event を待機する
_all_merged() {
  local wave="$1"
  local expected
  expected=$(_get_wave_issue_count "$wave")

  if [[ -z "$expected" || "$expected" -eq 0 ]]; then
    echo "[wave-progress-watchdog] WARN: no queue entry found for wave ${wave} — cannot confirm all-merged" >&2
    return 1
  fi

  local merged
  merged=$(_count_merged_events "$wave")
  echo "[wave-progress-watchdog] DEBUG: wave=${wave} expected=${expected} merged=${merged}" >&2

  [[ "$merged" -ge "$expected" ]]
}

# AC-3: completed-flag による idempotency（spawn once — 再 spawn 防止）
_is_wave_completed() {
  local wave="$1"
  [[ -f "${SUPERVISOR_DIR}/locks/wave-${wave}-completed.flag" ]]
}

_mark_wave_completed() {
  local wave="$1"
  touch "${SUPERVISOR_DIR}/locks/wave-${wave}-completed.flag"
}

# AC-7: wave-queue.json の current_wave を atomic 更新（mktemp → mv）
# auto-next-spawn.sh の dequeue 完了後に watchdog が順序を保証して更新する
_atomic_update_current_wave() {
  local new_wave="$1"
  [[ ! -f "$WAVE_QUEUE_FILE" ]] && return 0
  local tmp
  tmp=$(mktemp "${WAVE_QUEUE_FILE}.XXXXXX")
  if jq --argjson nw "$new_wave" '.current_wave = $nw' "$WAVE_QUEUE_FILE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$WAVE_QUEUE_FILE"
    echo "[wave-progress-watchdog] INFO: current_wave atomically updated to ${new_wave}"
  else
    rm -f "$tmp"
    echo "[wave-progress-watchdog] WARN: failed to atomic update current_wave in wave-queue.json" >&2
  fi
}

# ---- メインループ（polling） ----
echo "[wave-progress-watchdog] 起動: SUPERVISOR_DIR=${SUPERVISOR_DIR} POLL_INTERVAL=${POLL_INTERVAL_SEC}s"

while true; do
  if [[ ! -f "$WAVE_QUEUE_FILE" ]]; then
    sleep "$POLL_INTERVAL_SEC"
    continue
  fi

  current_wave=$(_get_current_wave)
  if [[ -z "$current_wave" || "$current_wave" -eq 0 ]]; then
    sleep "$POLL_INTERVAL_SEC"
    continue
  fi

  # completed-flag で idempotency（AC-3: 既に spawn 済みなら skip）
  if _is_wave_completed "$current_wave"; then
    sleep "$POLL_INTERVAL_SEC"
    continue
  fi

  # AC-5: 全 Issue merged 判定（未完了は spawn せず次 event を待機）
  if _all_merged "$current_wave"; then
    echo "[wave-progress-watchdog] INFO: wave ${current_wave} — all issues merged, invoking auto-next-spawn.sh"
    # completed-flag を立てて spawn once を保証（AC-3 idempotency）
    _mark_wave_completed "$current_wave"

    # AC-3: auto-next-spawn.sh を 1 回だけ呼び出す
    if [[ -x "$AUTO_NEXT_SPAWN_SCRIPT" ]]; then
      bash "$AUTO_NEXT_SPAWN_SCRIPT" \
        --queue "$WAVE_QUEUE_FILE" \
        --triggered-by "wave-progress-watchdog" || true
    else
      echo "[wave-progress-watchdog] WARN: auto-next-spawn.sh not found or not executable: ${AUTO_NEXT_SPAWN_SCRIPT}" >&2
    fi

    # AC-7: auto-next-spawn.sh の dequeue 完了後に current_wave を atomic 更新
    next_wave=$(_get_current_wave)
    if [[ -n "$next_wave" && "$next_wave" != "$current_wave" ]]; then
      _atomic_update_current_wave "$next_wave"
    fi
  else
    echo "[wave-progress-watchdog] DEBUG: wave ${current_wave} — not all merged, continue waiting" >&2
  fi

  sleep "$POLL_INTERVAL_SEC"
done
