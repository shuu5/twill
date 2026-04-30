#!/usr/bin/env bash
# observer-wave-check.sh — Wave 全 window IDLE-COMPLETED 判定ライブラリ (#1155)
#
# Usage (source):
#   source observer-wave-check.sh
#   _all_current_wave_idle_completed "$wave_queue_file" IDLE_COMPLETED_TS
#
# Returns:
#   exit 0  → 同 Wave 全 window が IDLE-COMPLETED（next-spawn 可）
#   exit 1  → 同 Wave に active window が残存（next-spawn skip）
#
# SRP: _all_current_wave_idle_completed のみ定義。_check_idle_completed は observer-idle-check.sh 参照。

# _all_current_wave_idle_completed wave_queue_file ts_array_name
#
# 引数:
#   $1 = wave-queue.json パス
#   $2 = IDLE_COMPLETED_TS 連想配列の変数名（nameref 経由でアクセス）
#
# 判定基準（AC-3）:
#   (i)  wave-queue.json の current_wave を取得
#   (ii) tmux list-windows で ^(ap|wt|coi)-.*  パターンの window 集合を取得
#   (iii) 全 window で IDLE_COMPLETED_TS[$WIN] > 0 が真なら 0 を返す
_all_current_wave_idle_completed() {
  local queue_file="${1:-}"
  local ts_array_name="${2:-IDLE_COMPLETED_TS}"

  if [[ -z "$queue_file" || ! -f "$queue_file" ]]; then
    echo "[observer-wave-check] WARN: wave-queue.json not found: ${queue_file}" >&2
    return 1
  fi

  local current_wave
  current_wave=$(jq -r '.current_wave // empty' "$queue_file" 2>/dev/null || echo "")
  if [[ -z "$current_wave" ]]; then
    echo "[observer-wave-check] WARN: current_wave not found in ${queue_file}" >&2
    return 1
  fi

  # tmux list-windows から ^(ap|wt|coi)-.*  パターンの window を取得
  local wave_windows
  wave_windows=$(tmux list-windows -a -F '#{window_name}' 2>/dev/null \
    | grep -E '^(ap|wt|coi)-' || true)

  if [[ -z "$wave_windows" ]]; then
    echo "[observer-wave-check] WARN: no (ap|wt|coi)-* windows found" >&2
    return 1
  fi

  local win ts
  while IFS= read -r win; do
    [[ -z "$win" ]] && continue
    # nameref で IDLE_COMPLETED_TS[$WIN] を参照
    local -n _ts_ref="${ts_array_name}" 2>/dev/null || true
    ts="${_ts_ref[$win]:-0}"
    if [[ "$ts" -le 0 ]]; then
      echo "[observer-wave-check] active window found: ${win} (IDLE_COMPLETED_TS=0)" >&2
      return 1
    fi
  done <<< "$wave_windows"

  return 0
}
