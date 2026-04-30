#!/usr/bin/env bash
# inject-next-workflow.sh — inject_next_workflow() 単独ライブラリ（Issue #720）
# autopilot-orchestrator.sh から source される。単体テストからも直接 source 可能。
# 依存: cleanup_worker() は呼び出し元で定義されていること

# グローバル連想配列宣言（-g で関数内 source でもグローバルスコープに宣言）
# -A のみ指定（=() なし）で既存の値はリセットしない
declare -gA RESOLVE_FAIL_COUNT 2>/dev/null || true
declare -gA RESOLVE_FAIL_FIRST_TS 2>/dev/null || true
declare -gA INJECT_TIMEOUT_COUNT 2>/dev/null || true
declare -gA NUDGE_COUNTS 2>/dev/null || true
declare -gA LAST_STATE_MTIME 2>/dev/null || true
declare -gA LAST_STAGNATE_WARN_TS 2>/dev/null || true

# inject_next_workflow: current_step terminal 値を検知して次の workflow skill を tmux inject する（ADR-018）
# 引数: issue, window_name, entry（省略時は _default:${issue}）
# 戻り値: 0=inject 成功、1=失敗（タイムアウト / resolve 失敗 / バリデーション失敗）、2=force-exit（status=failed 書き込み済み）
inject_next_workflow() {
  local issue="$1"
  local window_name="$2"
  local entry="${3:-_default:${issue}}"

  # --- trace ログファイル ---
  mkdir -p "${AUTOPILOT_DIR}/trace" 2>/dev/null || true  # SUMMARY_MODE 等での再利用を考慮して関数内でも保証
  local _trace_log="${AUTOPILOT_DIR}/trace/inject-$(date -u +%Y%m%d).log"
  local _trace_ts
  _trace_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # --- resolve_next_workflow CLI で次の workflow を決定 ---
  local next_skill next_skill_exit=0
  next_skill=$(python3 -m twl.autopilot.resolve_next_workflow --issue "$issue" 2>/dev/null) || next_skill_exit=$?
  if [[ "$next_skill_exit" -ne 0 || -z "$next_skill" ]]; then
    if [[ "$next_skill_exit" -eq 1 ]]; then
      # NOT_READY: non-terminal step（ポーリング中の正常状態）→ TRACE のみ（#707）
      echo "[${_trace_ts}] issue=${issue} category=RESOLVE_NOT_READY exit=${next_skill_exit} result=skip" >> "$_trace_log" 2>/dev/null || true
    else
      # ERROR: 予期せぬ失敗 → WARNING + TRACE（#707）
      echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 予期せぬエラー (exit=${next_skill_exit}) — inject スキップ" >&2
      echo "[${_trace_ts}] issue=${issue} category=RESOLVE_ERROR exit=${next_skill_exit} result=skip" >> "$_trace_log" 2>/dev/null || true
    fi

    # --- stagnate 検知（RESOLVE_FAILED 連続カウント + mtime progress signal） ---
    # AC-2/6: 関数スコープ宣言（二重宣言パターン — source 先での初期化保証）
    declare -gA LAST_STATE_MTIME 2>/dev/null || true
    declare -gA LAST_STAGNATE_WARN_TS 2>/dev/null || true

    local _now
    _now=$(date +%s 2>/dev/null || echo 0)

    # AC-1/3: mtime チェックは FAIL_COUNT インクリメントより前に実施
    local _state_file="${AUTOPILOT_DIR}/issues/issue-${issue}.json"
    local _current_mtime=0
    _current_mtime=$(stat -c '%Y' "$_state_file" 2>/dev/null || echo 0)
    local _last_mtime="${LAST_STATE_MTIME[$entry]:-0}"
    if (( _current_mtime > _last_mtime )); then
      # mtime 進行 → RESOLVE_FAIL カウントリセット（AC-7: LAST_STAGNATE_WARN_TS はリセットしない）
      RESOLVE_FAIL_COUNT[$entry]=0
      RESOLVE_FAIL_FIRST_TS[$entry]=""
    fi
    LAST_STATE_MTIME[$entry]="$_current_mtime"

    local _fail_count="${RESOLVE_FAIL_COUNT[$entry]:-0}"
    if [[ "$_fail_count" -eq 0 ]]; then
      RESOLVE_FAIL_FIRST_TS[$entry]="$_now"
    fi
    RESOLVE_FAIL_COUNT[$entry]=$(( _fail_count + 1 ))
    local _elapsed=$(( _now - ${RESOLVE_FAIL_FIRST_TS[$entry]:-_now} ))
    if (( _elapsed >= AUTOPILOT_STAGNATE_SEC )); then
      # AC-5/9: WARN rate limit（AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC 既定 60s）
      local _warn_interval="${AUTOPILOT_STAGNATE_WARN_INTERVAL_SEC:-60}"
      local _last_warn_ts="${LAST_STAGNATE_WARN_TS[$entry]:-0}"
      local _warn_elapsed=$(( _now - _last_warn_ts ))
      # AC-8: trace log は rate limit に関わらず常に記録
      echo "[${_trace_ts}] issue=${issue} skill=RESOLVE_FAILED result=stagnate elapsed=${_elapsed}s count=${RESOLVE_FAIL_COUNT[$entry]}" >> "$_trace_log" 2>/dev/null || true
      if (( _warn_elapsed >= _warn_interval )); then
        echo "[orchestrator] WARN: issue=${issue} stagnate detected (RESOLVE_FAILED ${RESOLVE_FAIL_COUNT[$entry]} 回, ${_elapsed}s >= AUTOPILOT_STAGNATE_SEC=${AUTOPILOT_STAGNATE_SEC})" >&2
        LAST_STAGNATE_WARN_TS[$entry]="$_now"
      fi
    fi

    return 1
  fi
  # inject 成功時は RESOLVE_FAIL カウントをリセット
  RESOLVE_FAIL_COUNT[$entry]=0
  RESOLVE_FAIL_FIRST_TS[$entry]=""
  LAST_STAGNATE_WARN_TS[$entry]=""  # AC-7: inject 成功時にリセット（mtime 変化時はリセットしない）

  # --- allow-list バリデーション（コマンドインジェクション防止） ---
  # 許可: /twl:workflow-<kebab> 形式（/twl:workflow-pr-merge を含む。#744: pr-merge skip 分岐を削除）
  local _skill_safe
  _skill_safe="${next_skill//$'\n'/}"  # 改行除去（ログインジェクション防止）
  if [[ ! "$_skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
    echo "[orchestrator] Issue #${issue}: WARNING: 不正な workflow skill '${_skill_safe:0:200}' — inject スキップ" >&2
    echo "[${_trace_ts}] issue=${issue} skill=INVALID result=skip reason=\"invalid skill name\"" >> "$_trace_log" 2>/dev/null || true
    return 1
  fi
  # AC-4 (#744, #874): workflow-pr-merge は merge-ready 状態を「作成する」skill のため、
  # inject 時点で status != "merge-ready" は正常動作 (AC-4 設計意図通り)。
  # 以前は WARNING レベルで記録していたが、Phase C #871 audit で Pilot stall 原因と誤診断
  # されていたことが判明 (#874: red-herring 解消、DEBUG 降格)。
  if [[ "$_skill_safe" == "/twl:workflow-pr-merge" ]]; then
    local _pr_merge_status
    _pr_merge_status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status 2>/dev/null || echo "")
    if [[ "$_pr_merge_status" != "merge-ready" ]]; then
      echo "[AUTOPILOT_DEBUG] [orchestrator] Issue #${issue}: pr-merge inject — status=${_pr_merge_status} (AC-4 通り、merge-ready 未成立は仕様)" >&2
      echo "[${_trace_ts}] issue=${issue} category=INJECT_PR_MERGE_DEBUG skill=${_skill_safe} status=${_pr_merge_status} result=debug reason=\"status not merge-ready, AC-4 expected behavior\"" >> "$_trace_log" 2>/dev/null || true
    fi
  fi

  # --- session-state.sh ベースの input-waiting 検出 ---
  # #707: tmux capture-pane + regex から session-state.sh state に置換。
  # #722: exponential backoff ループを session-state.sh wait --timeout 30 に置換。
  # 1秒間隔ポーリングで短い input-waiting ウィンドウ（1-3秒）を確実に検出する。
  # USE_SESSION_STATE=false 時は tmux フォールバックを維持（session-state.sh 非存在環境向け、設計上意図的）。
  local prompt_found=0
  if [[ "${USE_SESSION_STATE:-false}" == "true" ]]; then
    if "$SESSION_STATE_CMD" wait "$window_name" input-waiting --timeout 30 2>/dev/null; then
      prompt_found=1
    fi
  else
    # session-state.sh 非利用時フォールバック: tmux capture-pane + regex
    local _prompt_re='[>$❯][[:space:]]*$'
    local pane_tail
    for _i in 1 2 3; do
      pane_tail=$(tmux capture-pane -t "$window_name" -p 2>/dev/null | tail -6 || true)
      while IFS= read -r _line; do
        if [[ "$_line" =~ $_prompt_re ]]; then
          prompt_found=1
          break
        fi
      done <<< "$pane_tail"
      if [[ "$prompt_found" -eq 1 ]]; then
        break
      fi
      sleep $(( 2 ** _i ))  # 2s, 4s, 8s
    done
  fi

  if [[ "$prompt_found" -eq 0 ]]; then
    echo "[orchestrator] Issue #${issue}: WARNING: inject タイムアウト — ${POLL_INTERVAL:-10}秒後に再チェック" >&2
    echo "[${_trace_ts}] issue=${issue} category=INJECT_TIMEOUT skill=${_skill_safe} result=timeout reason=\"input-waiting not detected within 30s\"" >> "$_trace_log" 2>/dev/null || true
    # AC-2 #744: pr-merge 限定 timeout カウンタ — 上限超過で force-exit
    if [[ "$_skill_safe" == "/twl:workflow-pr-merge" ]]; then
      INJECT_TIMEOUT_COUNT[$entry]=$(( ${INJECT_TIMEOUT_COUNT[$entry]:-0} + 1 ))
      local _inject_max="${DEV_AUTOPILOT_INJECT_TIMEOUT_MAX:-5}"
      if (( INJECT_TIMEOUT_COUNT[$entry] > _inject_max )); then
        echo "[orchestrator] Issue #${issue}: CRITICAL: pr-merge inject timeout 上限超過 (${INJECT_TIMEOUT_COUNT[$entry]} > ${_inject_max}) — status=failed で force-exit" >&2
        echo "[${_trace_ts}] issue=${issue} category=INJECT_EXHAUSTED skill=${_skill_safe} count=${INJECT_TIMEOUT_COUNT[$entry]} max=${_inject_max} result=force_exit" >> "$_trace_log" 2>/dev/null || true
        python3 -m twl.autopilot.state write --type issue --issue "$issue" --role pilot \
          --set "status=failed" \
          --set 'failure={"reason":"inject_exhausted_pr_merge","step":"inject_next_workflow"}' 2>/dev/null || true
        cleanup_worker "$issue" "$entry"
        return 2  # force-exit: 呼び出し元は LAST_INJECTED_STEP を更新しない（status=failed 書き込み済み）
      fi
    fi
    return 1
  fi

  # --- inject 実行（バリデーション済みの _skill_safe を使用） ---
  echo "[orchestrator] Issue #${issue}: inject_next_workflow — ${_skill_safe}" >&2
  local _send_err
  _send_err=$(tmux send-keys -t "$window_name" "$_skill_safe" Enter 2>&1) || {
    _send_err="${_send_err//$'\n'/ }"  # ログインジェクション防止（改行除去）
    echo "[orchestrator] Issue #${issue}: WARNING: tmux send-keys 失敗 — ${_send_err}" >&2
    local _err_ts
    _err_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[${_err_ts}] issue=${issue} skill=${_skill_safe} result=error reason=\"tmux send-keys failed: ${_send_err}\"" >> "$_trace_log" 2>/dev/null || true
    return 1
  }

  # --- trace ログ: inject 成功（タイムスタンプを inject 完了後に再取得） ---
  local _success_ts
  _success_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # AC-4 #744: status / current_step / pr / branch を trace log に追記（改行除去でログインジェクション防止）
  local _inj_status _inj_step _inj_pr _inj_branch
  _inj_status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field status 2>/dev/null || echo "")
  _inj_step=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field current_step 2>/dev/null || echo "")
  _inj_pr=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field pr 2>/dev/null || echo "")
  _inj_branch=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field branch 2>/dev/null || echo "")
  _inj_status="${_inj_status//$'\n'/ }"
  _inj_step="${_inj_step//$'\n'/ }"
  _inj_pr="${_inj_pr//$'\n'/ }"
  _inj_branch="${_inj_branch//$'\n'/ }"
  echo "[${_success_ts}] issue=${issue} category=INJECT_SUCCESS skill=${_skill_safe} result=success status=${_inj_status} current_step=${_inj_step} pr=${_inj_pr} branch=${_inj_branch}" >> "$_trace_log" 2>/dev/null || true
  # AC-2 #744: inject 成功時に pr-merge timeout カウンタをリセット
  INJECT_TIMEOUT_COUNT[$entry]=0

  # --- inject 履歴記録（ADR-018: workflow_done クリアを廃止、workflow_injected で追跡）---
  local injected_at
  injected_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  python3 -m twl.autopilot.state write --type issue --issue "$issue" --role pilot \
    --set "workflow_injected=${_skill_safe}" \
    --set "injected_at=${injected_at}" 2>/dev/null || true

  # --- NUDGE_COUNTS リセット ---
  NUDGE_COUNTS[$entry]=0

  return 0
}
