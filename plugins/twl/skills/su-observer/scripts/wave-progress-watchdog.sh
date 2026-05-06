#!/usr/bin/env bash
# wave-progress-watchdog.sh — Wave PR 進行監視デーモン (#1429) + gh API polling fallback (#1432)
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
#   GH_API_FALLBACK_INTERVAL_SEC    Layer 3 gh API polling 間隔（デフォルト: 60 秒）
#
# 動作:
#   Layer 2: .supervisor/events/wave-${current_wave}-pr-merged-*.json を polling 監視し、
#            current_wave の全 Issue が merged された時点で auto-next-spawn.sh を 1 回だけ呼び出す。
#   Layer 3: Layer 2 signal が存在しない場合、gh API polling で PR merge 状態を確認する fallback。
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
GH_API_FALLBACK_INTERVAL_SEC="${GH_API_FALLBACK_INTERVAL_SEC:-60}"
_GH_API_FALLBACK_MAX_BACKOFF=600
# テスト用: 1 回のポーリングのみ実行して終了（SINGLE_POLL_TEST_MODE=1）
SINGLE_POLL_TEST_MODE="${SINGLE_POLL_TEST_MODE:-0}"

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

# ---- Layer 2 ヘルパー関数 ----

_get_current_wave() {
  [[ ! -f "$WAVE_QUEUE_FILE" ]] && { echo ""; return 1; }
  jq -r '.current_wave // empty' "$WAVE_QUEUE_FILE" 2>/dev/null || echo ""
}

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

_is_wave_completed() {
  local wave="$1"
  [[ -f "${SUPERVISOR_DIR}/locks/wave-${wave}-completed.flag" ]]
}

_mark_wave_completed() {
  local wave="$1"
  touch "${SUPERVISOR_DIR}/locks/wave-${wave}-completed.flag"
}

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

_invoke_auto_next_spawn() {
  if [[ -x "$AUTO_NEXT_SPAWN_SCRIPT" ]]; then
    bash "$AUTO_NEXT_SPAWN_SCRIPT" \
      --queue "$WAVE_QUEUE_FILE" \
      --triggered-by "wave-progress-watchdog" \
      --target-wave "$1" || true
  else
    echo "[wave-progress-watchdog] WARN: auto-next-spawn.sh not found or not executable: ${AUTO_NEXT_SPAWN_SCRIPT}" >&2
  fi
  next_wave=$(_get_current_wave)
  if [[ -n "$next_wave" && "$next_wave" != "$1" ]]; then
    _atomic_update_current_wave "$next_wave"
  fi
}

# ---- Layer 3: gh API polling fallback (#1432) ----

_gh_api_etag_file() {
  local wave_n="$1"
  echo "/tmp/.wave-watchdog-etag-${wave_n}.txt"
}

_append_intervention_log() {
  mkdir -p "$SUPERVISOR_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "${SUPERVISOR_DIR}/intervention-log.md" 2>/dev/null || true
}

# gh auth 確認（失敗時は skip、daemon を crash させない）
_gh_auth_ok() {
  if ! gh auth status > /dev/null 2>&1; then
    _append_intervention_log "WARN: wave-progress-watchdog gh auth skip: gh auth status failed"
    return 1
  fi
  return 0
}

# Layer 3 gh API polling: 0=未全マージ/skip, 1=全マージ検出, 2=rate-limit
poll_gh_api_fallback() {
  local wave_n="$1"

  # wave_n は正整数のみ許可（path traversal・glob injection 防止）
  if ! [[ "$wave_n" =~ ^[1-9][0-9]*$ ]]; then
    echo "[wave-progress-watchdog] WARN: invalid wave_n '${wave_n}' — skip gh API polling" >&2
    return 0
  fi

  # Layer 1 signal 存在時は Layer 3 skip（duplicate fire 抑止）
  if ls "${SUPERVISOR_DIR}/events/wave-${wave_n}-pr-merged-"*.json 2>/dev/null | grep -q .; then
    return 0
  fi

  # gh auth チェック
  if ! _gh_auth_ok; then
    return 0
  fi

  # ETag キャッシュ読み込み（消失時はフルポーリングに degradation）
  local etag_file
  etag_file="$(_gh_api_etag_file "$wave_n")"
  local etag=""
  [[ -f "$etag_file" ]] && etag=$(cat "$etag_file" 2>/dev/null || echo "")

  # gh api 呼び出し（ETag If-None-Match, --include でヘッダ取得）
  local gh_args=("api" "/repos/{owner}/{repo}/pulls?state=closed&per_page=100" "--include")
  [[ -n "$etag" ]] && gh_args+=("-H" "If-None-Match: ${etag}")

  local response http_status
  response=$(gh "${gh_args[@]}" 2>&1)
  http_status=$?

  if [[ "$http_status" -ne 0 ]]; then
    if echo "$response" | grep -qiE 'rate limit|API rate|exceeded'; then
      return 2
    fi
    echo "[wave-progress-watchdog] WARN: gh api failed (exit=${http_status})" >&2
    return 0
  fi

  # 304 Not Modified — query 消費なし
  if echo "$response" | head -1 | grep -q "^HTTP/.*304"; then
    echo "[wave-progress-watchdog] INFO: 304 Not Modified for wave ${wave_n}"
    return 0
  fi

  # ETag 更新
  local new_etag
  new_etag=$(echo "$response" | grep -i "^etag:" | head -1 | sed 's/^[Ee][Tt][Aa][Gg]:[[:space:]]*//' | tr -d '\r')
  [[ -n "$new_etag" ]] && echo "$new_etag" > "$etag_file"

  # JSON ボディ部分を取得
  local json_body
  json_body=$(echo "$response" | awk '/^\[/{p=1} p{print}')
  [[ -z "$json_body" ]] && return 0

  # current_wave の issues 取得（--argjson で jq injection 防止）
  local wave_issues
  wave_issues=$(jq -r --argjson w "$wave_n" \
    '.queue[] | select(.wave == $w) | .issues[]' \
    "$WAVE_QUEUE_FILE" 2>/dev/null || echo "")
  [[ -z "$wave_issues" ]] && return 0

  # 各 issue の PR merged 確認
  local all_merged=1
  local issue_num
  while IFS= read -r issue_num; do
    [[ -z "$issue_num" ]] && continue
    local pr_merged
    pr_merged=$(echo "$json_body" | jq -r \
      --argjson inum "$issue_num" \
      '[.[] | select(
          (.body // "" | test("(Closes|Fixes|Resolves)[[:space:]]+#" + ($inum | tostring); "i")) or
          (.head.ref // "" | test("/" + ($inum | tostring) + "[-_]"; ""))
        ) | .merged_at] | map(select(. != null)) | length > 0' 2>/dev/null || echo "false")
    if [[ "$pr_merged" != "true" ]]; then
      all_merged=0
      break
    fi
  done <<< "$wave_issues"

  [[ "$all_merged" -eq 1 ]] && return 1
  return 0
}

# ---- メインループ ----
echo "[wave-progress-watchdog] 起動: SUPERVISOR_DIR=${SUPERVISOR_DIR} POLL_INTERVAL=${POLL_INTERVAL_SEC}s GH_API_FALLBACK_INTERVAL=${GH_API_FALLBACK_INTERVAL_SEC}s"

_gh_backoff="$GH_API_FALLBACK_INTERVAL_SEC"
_gh_poll_counter=0
_gh_poll_every=$(( GH_API_FALLBACK_INTERVAL_SEC / POLL_INTERVAL_SEC ))
[[ "$_gh_poll_every" -lt 1 ]] && _gh_poll_every=1

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

  if _is_wave_completed "$current_wave"; then
    sleep "$POLL_INTERVAL_SEC"
    continue
  fi

  # Layer 2: events/ signal ファイルによる判定
  if _all_merged "$current_wave"; then
    echo "[wave-progress-watchdog] INFO: wave ${current_wave} — Layer 2 signal: all merged, invoking auto-next-spawn.sh"
    _invoke_auto_next_spawn "$current_wave"
    _gh_backoff="$GH_API_FALLBACK_INTERVAL_SEC"
    sleep "$POLL_INTERVAL_SEC"
    continue
  fi

  # Layer 3: gh API polling fallback（GH_API_FALLBACK_INTERVAL_SEC 間隔）
  _gh_poll_counter=$(( _gh_poll_counter + 1 ))
  if [[ "$(( _gh_poll_counter % _gh_poll_every ))" -eq 0 ]]; then
    poll_gh_api_fallback "$current_wave"
    _gh_result=$?

    case "$_gh_result" in
      1)
        echo "[wave-progress-watchdog] INFO: wave ${current_wave} — Layer 3 gh API: all PRs merged, invoking auto-next-spawn.sh"
        _append_intervention_log "wave-progress-watchdog: Layer 3 gh API fallback triggered for wave ${current_wave}"
        _invoke_auto_next_spawn "$current_wave"
        _gh_backoff="$GH_API_FALLBACK_INTERVAL_SEC"
        ;;
      2)
        _gh_backoff=$(( _gh_backoff * 2 ))
        [[ "$_gh_backoff" -gt "$_GH_API_FALLBACK_MAX_BACKOFF" ]] && _gh_backoff="$_GH_API_FALLBACK_MAX_BACKOFF"
        _gh_poll_every=$(( _gh_backoff / POLL_INTERVAL_SEC ))
        [[ "$_gh_poll_every" -lt 1 ]] && _gh_poll_every=1
        echo "[wave-progress-watchdog] WARN: rate-limited, gh API backoff to ${_gh_backoff}s" >&2
        _append_intervention_log "wave-progress-watchdog: rate-limited (wave=${current_wave}), backoff=${_gh_backoff}s"
        ;;
      *)
        _gh_backoff="$GH_API_FALLBACK_INTERVAL_SEC"
        ;;
    esac
  fi

  [[ "$SINGLE_POLL_TEST_MODE" == "1" ]] && exit 0
  sleep "$POLL_INTERVAL_SEC"
done
