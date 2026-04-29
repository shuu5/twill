#!/usr/bin/env bash
# observer-parallel-check.sh: 並列 spawn 可否判定ライブラリ（source 専用）
#
# 背景（Issue #1116, pitfalls-catalog.md §11.3）:
#   observer が自律的に複数 controller を並列 spawn する際の条件判定を機械化する。
#   SKILL.md 文書のみでは observer LLM が「読まずに通過」するため、
#   spawn-controller.sh に統合して機械的 enforcement を実現する。
#
# 使用方法:
#   source "$(dirname "$0")/../scripts/lib/observer-parallel-check.sh"
#   _check_parallel_spawn_eligibility && echo "≤4 並列 OK" || echo "spawn 不可"
#
# exit コード:
#   0: 全条件 PASS → ≤ 4 並列 OK
#   1: precondition 1つでも false → ≤ 2 並列 degrade（stderr に欠落 precondition）
#   2: 必須条件 1つでも false → spawn 完全禁止（stderr に欠落必須条件）
#
# env var injection（テスト・override 用）:
#   OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS     - atomicity 保証用タイムスタンプ（秒）
#   OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE - "true"/"false"（必須条件1）
#   OBSERVER_PARALLEL_CHECK_MODE            - permission mode（必須条件2）
#   OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT - eligible controller 数（必須条件3）
#   OBSERVER_PARALLEL_CHECK_MONITOR_CLD     - "true"/"false"（precondition4）
#   OBSERVER_PARALLEL_CHECK_STATES          - controller states（space-separated）（precondition5）
#   OBSERVER_PARALLEL_CHECK_BUDGET_MIN      - budget 残量（分）（precondition6）
#   OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD - 閾値（分、default 150）
#
# NOTE: set -euo pipefail は意図的に省略（source 専用ライブラリ）

# ---------------------------------------------------------------------------
# check_controller_heartbeat_alive: controller の heartbeat が生存しているか確認
#
# 引数:
#   $1: snapshot_ts（秒）
#
# 出力:
#   "true" または "false"（stdout）
#
# 実装根拠（su-observer-supervise-channels.md L60-89）:
#   observer 自身の heartbeat 更新（writer=observer）は判定対象から除外する（§15.3）。
#   .supervisor/events/heartbeat-* ファイルの mtime を確認する。
# ---------------------------------------------------------------------------
check_controller_heartbeat_alive() {
  local snapshot_ts="${1:-$(date +%s)}"
  local supervisor_dir="${SUPERVISOR_DIR:-.supervisor}"
  local events_dir="${supervisor_dir}/events"
  local max_age=300  # 5分

  local found_alive=false
  local writer='' mtime=0
  if [[ -d "$events_dir" ]]; then
    while IFS= read -r -d '' hb_file; do
      # observer 自身の heartbeat は除外（writer=observer）
      writer=$(jq -r '.writer // "pilot"' "$hb_file" 2>/dev/null || echo "pilot")
      if [[ "$writer" == "observer" ]]; then
        continue
      fi

      # mtime チェック: snapshot_ts から max_age 秒以内に更新されていれば alive
      mtime=$(stat -c '%Y' "$hb_file" 2>/dev/null || echo "0")
      if (( snapshot_ts - mtime <= max_age )); then
        found_alive=true
        break
      fi
    done < <(find "$events_dir" -name "heartbeat-*" -type f -print0 2>/dev/null)
  fi

  echo "$found_alive"
}

# ---------------------------------------------------------------------------
# check_observer_mode: observer の permission mode を取得
#
# 出力:
#   "auto", "bypass", "default", "plan", etc.（stdout）
#
# 判定方法（§11.3 必須条件2）:
#   .supervisor/session.json の mode field を参照。
#   field 不在または空文字の場合は "unknown" を返す（fail-closed）。
# ---------------------------------------------------------------------------
check_observer_mode() {
  local supervisor_dir="${SUPERVISOR_DIR:-.supervisor}"
  local session_file="${supervisor_dir}/session.json"

  if [[ -f "$session_file" ]]; then
    local mode
    mode=$(jq -r '.mode // empty' "$session_file" 2>/dev/null || echo "")
    if [[ -n "$mode" ]]; then
      echo "$mode"
      return
    fi
  fi

  echo "unknown"
}

# ---------------------------------------------------------------------------
# count_eligible_controllers: eligible な controller 数を返す
#
# 引数:
#   $1: snapshot_ts（秒）
#
# 出力:
#   controller 数（stdout）
#
# 実装根拠（§11.3 必須条件3）:
#   tmux list-windows で (ap-|wt-co-).* パターンの window を count。
#   直近 30 秒以内に spawn された controller は false positive 回避のため除外。
# ---------------------------------------------------------------------------
count_eligible_controllers() {
  local snapshot_ts="${1:-$(date +%s)}"
  local recent_threshold=30

  local count=0
  while IFS= read -r window_name; do
    [[ -z "$window_name" ]] && continue
    # (ap-|wt-co-) パターンのみ対象
    if [[ ! "$window_name" =~ ^(ap-|wt-co-) ]]; then
      continue
    fi
    # 直近 30 秒以内 spawn の window を除外（LLM_INDICATORS 未 emit による false positive 回避）
    # window の pane-start-time で判定
    local start_time
    start_time=$(tmux display-message -t "$window_name" -p '#{pane_start_time}' 2>/dev/null || echo "0")
    if (( snapshot_ts - start_time < recent_threshold )); then
      continue
    fi
    (( count++ )) || true
  done < <(tmux list-windows -a -F '#{window_name}' 2>/dev/null || echo "")

  echo "$count"
}

# ---------------------------------------------------------------------------
# check_monitor_cld_observe_alive: Monitor tool と cld-observe-any が起動しているか確認
#
# 出力:
#   "true" または "false"（stdout）
#
# 実装根拠（§4.1, precondition4）:
#   プロセスリストから cld-observe-any の存在を確認する。
# ---------------------------------------------------------------------------
check_monitor_cld_observe_alive() {
  # cld-observe-any プロセスの存在確認
  if pgrep -f "cld-observe-any" >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

# ---------------------------------------------------------------------------
# get_controller_states: eligible controller の状態を返す
#
# 引数:
#   $1: snapshot_ts（秒）
#
# 出力:
#   space-separated list of states（S-2/S-3/S-4 等）（stdout）
#
# 実装根拠（precondition5）:
#   cld-observe-any --once --pattern で各 controller の状態を取得する。
# ---------------------------------------------------------------------------
get_controller_states() {
  local snapshot_ts="${1:-$(date +%s)}"
  local states=()
  local state=''
  while IFS= read -r window_name; do
    [[ -z "$window_name" ]] && continue
    if [[ ! "$window_name" =~ ^(ap-|wt-co-) ]]; then
      continue
    fi

    # session-state.sh で状態取得（SESSION_STATE_SH env var で override 可）
    state=$(bash "${SESSION_STATE_SH:-scripts/session-state.sh}" state "$window_name" 2>/dev/null || echo "S-0")
    states+=("$state")
  done < <(tmux list-windows -a -F '#{window_name}' 2>/dev/null || echo "")

  echo "${states[*]:-}"
}

# ---------------------------------------------------------------------------
# get_budget_minutes_remaining: budget 残量（分）を返す
#
# 出力:
#   残量分数（stdout）。取得不能時は -1
#
# 実装根拠（precondition6）:
#   cld-observe-any の get_budget_minutes() ロジックに準拠。
#   Pilot window の pane から budget 情報を抽出する。
# ---------------------------------------------------------------------------
get_budget_minutes_remaining() {
  local pilot_window="${PILOT_WINDOW:-}"

  if [[ -z "$pilot_window" ]]; then
    # supervisor/session.json から Pilot window を推定
    local session_file="${SUPERVISOR_DIR:-.supervisor}/session.json"
    if [[ -f "$session_file" ]]; then
      pilot_window=$(jq -r '.pilot_window // empty' "$session_file" 2>/dev/null || echo "")
    fi
  fi

  if [[ -z "$pilot_window" ]]; then
    echo "-1"
    return
  fi

  # budget 情報抽出（budget-detect.sh パターン準拠）
  local pane_content
  pane_content=$(tmux capture-pane -t "$pilot_window" -p -S -1 2>/dev/null || echo "")

  local budget_pct budget_raw
  budget_pct=$(echo "$pane_content" | grep -oP '5h:\K[0-9]+(?=%)' | tail -1 || echo "")
  budget_raw=$(echo "$pane_content" | grep -oP '5h:[0-9]+%\(\K[^\)]+' | tail -1 || echo "")

  if [[ -n "$budget_pct" && "$budget_pct" =~ ^[0-9]+$ ]]; then
    # 5h budget から残量計算: 300分 × (100 - 消費%) / 100
    echo $(( 300 * (100 - budget_pct) / 100 ))
  elif [[ -n "$budget_raw" ]]; then
    # 時間形式をパース
    if [[ "$budget_raw" =~ ^([0-9]+)h([0-9]+)m$ ]]; then
      echo $(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
    elif [[ "$budget_raw" =~ ^([0-9]+)h$ ]]; then
      echo $(( ${BASH_REMATCH[1]} * 60 ))
    elif [[ "$budget_raw" =~ ^([0-9]+)m$ ]]; then
      echo "${BASH_REMATCH[1]}"
    else
      echo "-1"
    fi
  else
    echo "-1"
  fi
}

# ---------------------------------------------------------------------------
# get_parallel_spawn_min_remaining_minutes: 並列 spawn 許可の budget 閾値（分）を返す
#
# 出力:
#   閾値分数（stdout）。default 150
#
# 実装根拠（precondition6）:
#   .supervisor/budget-config.json の parallel_spawn_min_remaining_minutes を参照。
#   既存 threshold_remaining_minutes(default 40) とは独立した新規 key。
# ---------------------------------------------------------------------------
get_parallel_spawn_min_remaining_minutes() {
  local config_file="${SUPERVISOR_DIR:-.supervisor}/budget-config.json"
  local default_threshold=150

  if [[ -f "$config_file" ]]; then
    local threshold
    threshold=$(jq -r '.parallel_spawn_min_remaining_minutes // empty' "$config_file" 2>/dev/null || echo "")
    if [[ -n "$threshold" && "$threshold" =~ ^[0-9]+$ ]]; then
      echo "$threshold"
      return
    fi
  fi

  echo "$default_threshold"
}

# ---------------------------------------------------------------------------
# _check_parallel_spawn_eligibility: 並列 spawn 可否を AND 評価する純関数
#
# 戻り値:
#   0: 全条件 PASS → ≤ 4 並列 OK
#   1: precondition 1つでも false → ≤ 2 並列 degrade（stderr に欠落 precondition）
#   2: 必須条件 1つでも false → spawn 完全禁止（stderr に欠落必須条件）
# ---------------------------------------------------------------------------
_check_parallel_spawn_eligibility() {
  local snapshot_ts="${OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS:-$(date +%s)}"

  # --- 各条件の評価 ---
  local heartbeat_alive="${OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE:-$(check_controller_heartbeat_alive "$snapshot_ts")}"
  local mode="${OBSERVER_PARALLEL_CHECK_MODE:-$(check_observer_mode)}"
  local controller_count="${OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT:-$(count_eligible_controllers "$snapshot_ts")}"
  local monitor_cld_alive="${OBSERVER_PARALLEL_CHECK_MONITOR_CLD:-$(check_monitor_cld_observe_alive)}"
  local controller_states="${OBSERVER_PARALLEL_CHECK_STATES:-$(get_controller_states "$snapshot_ts")}"
  local budget_min="${OBSERVER_PARALLEL_CHECK_BUDGET_MIN:-$(get_budget_minutes_remaining)}"
  local budget_threshold="${OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD:-$(get_parallel_spawn_min_remaining_minutes)}"

  # --- 必須条件評価（3つ, causally decisive） ---
  local missing_must=()

  # 必須条件1: controller heartbeat alive (≤ 5min)
  if [[ "$heartbeat_alive" != "true" ]]; then
    missing_must+=("heartbeat_alive=false: controller の heartbeat が 5分以内に更新されていない（§11.1）")
  fi

  # 必須条件2: permission mode が bypass または auto
  if [[ "$mode" != "bypass" && "$mode" != "auto" ]]; then
    missing_must+=("mode=${mode}: bypass または auto mode が必要（Layer A-D 自律実行可能性）")
  fi

  # 必須条件3: SU-4 整合: controller_count + 1 <= 4
  if (( controller_count + 1 > 4 )); then
    missing_must+=("controller_count=${controller_count}: +1=$(( controller_count + 1 )) > 4（SU-4 ≤5 整合違反）")
  fi

  if [[ ${#missing_must[@]} -gt 0 ]]; then
    echo "DENY: 必須条件不足 — spawn 完全禁止" >&2
    for msg in "${missing_must[@]}"; do
      echo "  - $msg" >&2
    done
    return 2
  fi

  # --- precondition 評価（3つ, derivative） ---
  local missing_pre=()

  # precondition4: Monitor + cld-observe-any 起動
  if [[ "$monitor_cld_alive" != "true" ]]; then
    missing_pre+=("monitor_cld_alive=false: Monitor tool + cld-observe-any が未起動（§4.1）")
  fi

  # precondition5: 全 eligible controller が S-2/S-3/S-4 のいずれか
  if [[ -n "$controller_states" ]]; then
    local state=''
    for state in $controller_states; do
      if [[ "$state" != "S-2" && "$state" != "S-3" && "$state" != "S-4" && \
            "$state" != "S-2 THINKING" && "$state" != "S-3 MENU-READY" && "$state" != "S-4 REVIEW-READY" ]]; then
        # S-0/S-1/S-5 等の不正状態を検出
        if [[ "$state" =~ ^S-[015] ]]; then
          missing_pre+=("controller_states に ${state} が含まれる: S-2/S-3/S-4 以外は precondition 違反（§4.10）")
          break
        fi
      fi
    done
  fi

  # precondition6: budget 残量 >= 閾値
  if [[ "$budget_min" != "-1" ]] && (( budget_min < budget_threshold )); then
    missing_pre+=("budget_min=${budget_min} < threshold=${budget_threshold}: budget 不足（[BUDGET-LOW] 閾値とは独立）")
  fi

  if [[ ${#missing_pre[@]} -gt 0 ]]; then
    echo "DEGRADE_TO_2: precondition 不足 — ≤ 2 並列に degrade" >&2
    for msg in "${missing_pre[@]}"; do
      echo "  - $msg" >&2
    done
    return 1
  fi

  return 0
}
