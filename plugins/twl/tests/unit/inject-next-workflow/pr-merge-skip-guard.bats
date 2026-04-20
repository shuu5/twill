#!/usr/bin/env bats
# pr-merge-skip-guard.bats
# Requirement: BATS テスト — pr-merge inject 経路の自動検証
# Spec: deltaspec/changes/issue-744/specs/orchestrator-pr-merge-guard.md
#
# 3 Scenarios:
#   (a) warning-fix 完了後に /twl:workflow-pr-merge が inject される
#   (b) status=merge-ready かつ LAST_INJECTED_STEP 更新済みの場合は重複 inject されない
#   (c) timeout 上限超過で status=failed と cleanup_worker が呼ばれる
#
# テスト double 方針:
#   autopilot-orchestrator.sh の inject_next_workflow() の修正後振る舞いを
#   dispatch スクリプト（pr-merge-744-dispatch.sh）として sandbox 内で再現する。
#   これにより実装前（TDD）でも仕様をテストとして確定できる。
#
# 環境変数（dispatch スクリプト制御用）:
#   NEXT_WORKFLOW              - resolve_next_workflow の返す skill 名
#   RESOLVE_EXIT               - resolve_next_workflow の終了コード（デフォルト: 0）
#   SESSION_STATE              - session-state.sh state の返す状態（デフォルト: "input-waiting"）
#   LAST_INJECTED_STEP_VALUE   - LAST_INJECTED_STEP[$entry] の初期値（デフォルト: ""）
#   CURRENT_STEP               - Worker の current_step 値（デフォルト: "warning-fix"）
#   INJECT_TIMEOUT_COUNT_INIT  - INJECT_TIMEOUT_COUNT[$entry] の初期値（デフォルト: 0）
#   DEV_AUTOPILOT_INJECT_TIMEOUT_MAX - timeout 上限（デフォルト: 5）
#   CALLS_LOG                  - 呼び出し記録ファイル
#   TRACE_LOG                  - trace ログファイルパス
#   STATE_FILE                 - state write 記録ファイル

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: inject_next_workflow() の #744 修正後振る舞いを再現する dispatch スクリプトを生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  TRACE_LOG="$SANDBOX/.autopilot/trace/inject-test.log"
  STATE_FILE="$SANDBOX/state.log"
  mkdir -p "$SANDBOX/.autopilot/trace"
  export CALLS_LOG TRACE_LOG STATE_FILE

  # ---------------------------------------------------------------------------
  # pr-merge-744-dispatch.sh:
  #   inject_next_workflow() の #744 修正後振る舞いを再現するテスト double
  #
  # #744 の修正仕様:
  #   - pr-merge / /twl:workflow-pr-merge 検出時は inject スキップしない（skip 分岐を削除）
  #     → 通常の allow-list バリデーション → input-waiting 検出 → tmux send-keys inject を通る
  #   - INJECT_TIMEOUT_COUNT[$entry] カウンタで連続 timeout を追跡
  #   - timeout 回数が DEV_AUTOPILOT_INJECT_TIMEOUT_MAX（デフォルト5）を超えた場合:
  #       state に status=failed + failure.reason=inject_exhausted_pr_merge を書き込み
  #       cleanup_worker を呼び出して force-exit
  #   - inject 成功時は INJECT_TIMEOUT_COUNT[$entry] を 0 にリセット
  #   - LAST_INJECTED_STEP[$entry] == current_step の場合は inject_next_workflow を呼ばない
  #     （重複防止: polling ループ側のガード — dispatch スクリプトでは呼び出しガード側を再現）
  # ---------------------------------------------------------------------------
  cat > "$SANDBOX/scripts/pr-merge-744-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# pr-merge-744-dispatch.sh
# inject_next_workflow() の #744 修正後振る舞いを再現するテスト double
#
# Usage: pr-merge-744-dispatch.sh <issue> <window_name> <entry>
set -uo pipefail

issue="$1"
window_name="$2"
entry="${3:-_default:${issue}}"

NEXT_WORKFLOW="${NEXT_WORKFLOW:-/twl:workflow-pr-merge}"
RESOLVE_EXIT="${RESOLVE_EXIT:-0}"
SESSION_STATE="${SESSION_STATE:-input-waiting}"
INJECT_TIMEOUT_COUNT_INIT="${INJECT_TIMEOUT_COUNT_INIT:-0}"
DEV_AUTOPILOT_INJECT_TIMEOUT_MAX="${DEV_AUTOPILOT_INJECT_TIMEOUT_MAX:-5}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"
TRACE_LOG="${TRACE_LOG:-/dev/null}"
STATE_FILE="${STATE_FILE:-/dev/null}"

trace_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$(dirname "$TRACE_LOG")" 2>/dev/null || true

# --- INJECT_TIMEOUT_COUNT をファイルで模倣（bash サブシェルでは連想配列は伝播しない）---
TIMEOUT_COUNT_FILE="${SANDBOX:-/tmp}/inject-timeout-count-${entry//[^a-zA-Z0-9]/_}"
if [[ ! -f "$TIMEOUT_COUNT_FILE" ]]; then
  echo "$INJECT_TIMEOUT_COUNT_INIT" > "$TIMEOUT_COUNT_FILE"
fi
_timeout_count=$(cat "$TIMEOUT_COUNT_FILE" 2>/dev/null || echo 0)

# --- resolve_next_workflow 呼び出し記録 ---
echo "resolve_next_workflow --issue $issue exit=$RESOLVE_EXIT" >> "$CALLS_LOG"

if [[ "$RESOLVE_EXIT" -ne 0 || -z "$NEXT_WORKFLOW" ]]; then
  if [[ "$RESOLVE_EXIT" -eq 1 ]]; then
    echo "[${trace_ts}] issue=${issue} category=RESOLVE_NOT_READY exit=${RESOLVE_EXIT} result=skip" >> "$TRACE_LOG"
  else
    echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 予期せぬエラー (exit=${RESOLVE_EXIT}) — inject スキップ" >&2
    echo "[${trace_ts}] issue=${issue} category=RESOLVE_ERROR exit=${RESOLVE_EXIT} result=skip" >> "$TRACE_LOG"
  fi
  exit 1
fi

next_skill="$NEXT_WORKFLOW"
_skill_safe="${next_skill//$'\n'/}"  # 改行除去（ログインジェクション防止）

# --- allow-list バリデーション ---
# #744 修正: pr-merge / /twl:workflow-pr-merge は skip 分岐を通らず、
# 通常の allow-list バリデーションを通過して inject に進む。
# 正規表現: ^/twl:workflow-[a-z][a-z0-9-]*$ は /twl:workflow-pr-merge を許可する。
if [[ ! "$_skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: 不正な workflow skill '${_skill_safe:0:200}' — inject スキップ" >&2
  echo "[${trace_ts}] issue=${issue} skill=INVALID result=skip reason=\"invalid skill name\"" >> "$TRACE_LOG"
  exit 1
fi

# --- session-state.sh ベースの input-waiting 検出 ---
# SESSION_STATE をカンマ区切りで呼び出し順に消費する
STATE_CALL_FILE="${SANDBOX:-/tmp}/state-call-count-$$"
echo "0" > "$STATE_CALL_FILE"

get_next_state() {
  local count
  count=$(cat "$STATE_CALL_FILE" 2>/dev/null || echo 0)
  IFS=',' read -ra _states <<< "$SESSION_STATE"
  local len="${#_states[@]}"
  local idx=$((count))
  local state_entry
  if (( idx < len )); then
    state_entry="${_states[$idx]}"
  else
    state_entry="${_states[$((len - 1))]}"
  fi
  echo $(( count + 1 )) > "$STATE_CALL_FILE"
  echo "$state_entry"
}

prompt_found=0
current_state=$(get_next_state)
echo "session-state state $window_name -> $current_state" >> "$CALLS_LOG"
if [[ "$current_state" == "input-waiting" ]]; then
  prompt_found=1
fi

if [[ "$prompt_found" -eq 0 ]]; then
  # タイムアウト: INJECT_TIMEOUT_COUNT をインクリメント
  _new_count=$(( _timeout_count + 1 ))
  echo "$_new_count" > "$TIMEOUT_COUNT_FILE"

  echo "[orchestrator] Issue #${issue}: WARNING: inject タイムアウト — 再チェック" >&2
  echo "[${trace_ts}] issue=${issue} category=INJECT_TIMEOUT skill=${_skill_safe} result=timeout reason=\"input-waiting not detected\"" >> "$TRACE_LOG"

  # --- timeout 上限超過: force-exit ---
  if (( _new_count > DEV_AUTOPILOT_INJECT_TIMEOUT_MAX )); then
    echo "[orchestrator] Issue #${issue}: ERROR: inject timeout 上限超過 (count=${_new_count} > max=${DEV_AUTOPILOT_INJECT_TIMEOUT_MAX}) — force-exit" >&2
    # state 書き込み
    echo "state_write status=failed" >> "$STATE_FILE"
    echo "state_write failure.reason=inject_exhausted_pr_merge" >> "$STATE_FILE"
    echo "[${trace_ts}] issue=${issue} category=INJECT_EXHAUSTED skill=${_skill_safe} result=force_exit count=${_new_count}" >> "$TRACE_LOG"
    # cleanup_worker 呼び出し
    echo "cleanup_worker called issue=${issue} entry=${entry}" >> "$CALLS_LOG"
    exit 2  # force-exit を示す特別な終了コード
  fi

  exit 1
fi

# --- inject 実行 ---
echo "tmux send-keys -t $window_name $_skill_safe" >> "$CALLS_LOG"

# --- inject 成功: INJECT_TIMEOUT_COUNT をリセット ---
echo "0" > "$TIMEOUT_COUNT_FILE"

_success_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[${_success_ts}] issue=${issue} category=INJECT_SUCCESS skill=${_skill_safe} result=success" >> "$TRACE_LOG"
echo "[orchestrator] Issue #${issue}: inject_next_workflow — ${_skill_safe}" >&2

# state 書き込み
echo "state_write workflow_injected=${_skill_safe}" >> "$STATE_FILE"

exit 0
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/pr-merge-744-dispatch.sh"

  # SANDBOX 変数を dispatch スクリプト内から参照できるよう export
  export SANDBOX
}

teardown() {
  common_teardown
}

# ===========================================================================
# Scenario (a): warning-fix 完了後に /twl:workflow-pr-merge が inject される
# WHEN Worker の current_step=warning-fix、status=running、
#      resolve_next_workflow が /twl:workflow-pr-merge を返す
# THEN tmux send-keys に /twl:workflow-pr-merge が含まれ、
#      trace log に category=INJECT_SUCCESS skill=/twl:workflow-pr-merge が記録される
# ===========================================================================

@test "issue-744[(a)]: pr-merge inject — tmux send-keys に /twl:workflow-pr-merge が含まれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  grep -q "tmux send-keys -t ap-#744 /twl:workflow-pr-merge" "$CALLS_LOG"
}

@test "issue-744[(a)]: pr-merge inject — trace log に category=INJECT_SUCCESS が記録される" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  grep -q "category=INJECT_SUCCESS" "$TRACE_LOG"
}

@test "issue-744[(a)]: pr-merge inject — trace log に skill=/twl:workflow-pr-merge が含まれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  grep "category=INJECT_SUCCESS" "$TRACE_LOG" | grep -q "skill=/twl:workflow-pr-merge"
}

@test "issue-744[(a)]: pr-merge inject — [orchestrator] inject ログを出力する" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  assert_output --partial "[orchestrator] Issue #744: inject_next_workflow — /twl:workflow-pr-merge"
}

@test "issue-744[(a)]: pr-merge inject — resolve_next_workflow が呼ばれている" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  grep -q "resolve_next_workflow --issue 744" "$CALLS_LOG"
}

@test "issue-744[(a)]: pr-merge inject — state に workflow_injected が記録される" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  grep -q "state_write workflow_injected=/twl:workflow-pr-merge" "$STATE_FILE"
}

@test "issue-744[(a)]: pr-merge inject — current_step=warning-fix で inject が通過する（旧 skip 分岐が存在しない確認）" {
  # #744 修正前の実装では pr-merge/workflow-pr-merge を検出すると inject をスキップし exit 0 を返す。
  # 修正後は inject を実行するため tmux send-keys が呼ばれる。
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  CURRENT_STEP="warning-fix" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

# ===========================================================================
# Scenario (b): status=merge-ready かつ LAST_INJECTED_STEP 更新済みの場合は重複 inject されない
# WHEN LAST_INJECTED_STEP[$entry]=warning-fix、current_step が同値
# THEN inject_next_workflow が呼ばれず、run_merge_gate への流入のみが起こる
#
# 注: この重複防止ガードは polling ループ側（poll_single / poll_phase）で実装される。
#     dispatch スクリプトは「inject_next_workflow を呼ぶかどうかの判断」を再現する
#     polling-guard.sh で検証する。
# ===========================================================================

@test "issue-744[(b)]: 重複 inject 防止 — LAST_INJECTED_STEP=current_step なら inject_next_workflow を呼ばない" {
  # polling-guard.sh: LAST_INJECTED_STEP と current_step の一致判定を再現
  cat > "$SANDBOX/scripts/polling-guard.sh" << 'GUARD_EOF'
#!/usr/bin/env bash
# polling-guard.sh
# polling ループの重複 inject 防止ガードを再現（ADR-018）
set -uo pipefail

CURRENT_STEP="${CURRENT_STEP:-warning-fix}"
LAST_INJECTED_STEP_VALUE="${LAST_INJECTED_STEP_VALUE:-}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"

_cur_step="$CURRENT_STEP"

# ADR-018: LAST_INJECTED_STEP[$entry] == current_step なら inject_next_workflow を呼ばない
if [[ -n "$_cur_step" && "$LAST_INJECTED_STEP_VALUE" != "$_cur_step" ]]; then
  echo "inject_next_workflow called" >> "$CALLS_LOG"
else
  # 重複防止ガード発動: run_merge_gate のみ実行
  echo "inject_skipped_duplicate step=${_cur_step}" >> "$CALLS_LOG"
  echo "run_merge_gate called" >> "$CALLS_LOG"
fi

exit 0
GUARD_EOF
  chmod +x "$SANDBOX/scripts/polling-guard.sh"

  CURRENT_STEP="warning-fix" \
  LAST_INJECTED_STEP_VALUE="warning-fix" \
    run bash "$SANDBOX/scripts/polling-guard.sh"

  assert_success
  ! grep -q "inject_next_workflow called" "$CALLS_LOG" 2>/dev/null
}

@test "issue-744[(b)]: 重複 inject 防止 — LAST_INJECTED_STEP=current_step 時に run_merge_gate が呼ばれる" {
  cat > "$SANDBOX/scripts/polling-guard.sh" << 'GUARD_EOF'
#!/usr/bin/env bash
set -uo pipefail
CURRENT_STEP="${CURRENT_STEP:-warning-fix}"
LAST_INJECTED_STEP_VALUE="${LAST_INJECTED_STEP_VALUE:-}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"
_cur_step="$CURRENT_STEP"
if [[ -n "$_cur_step" && "$LAST_INJECTED_STEP_VALUE" != "$_cur_step" ]]; then
  echo "inject_next_workflow called" >> "$CALLS_LOG"
else
  echo "inject_skipped_duplicate step=${_cur_step}" >> "$CALLS_LOG"
  echo "run_merge_gate called" >> "$CALLS_LOG"
fi
exit 0
GUARD_EOF
  chmod +x "$SANDBOX/scripts/polling-guard.sh"

  CURRENT_STEP="warning-fix" \
  LAST_INJECTED_STEP_VALUE="warning-fix" \
    run bash "$SANDBOX/scripts/polling-guard.sh"

  assert_success
  grep -q "run_merge_gate called" "$CALLS_LOG"
}

@test "issue-744[(b)]: 重複 inject 防止 — LAST_INJECTED_STEP が空なら inject_next_workflow を呼ぶ" {
  cat > "$SANDBOX/scripts/polling-guard.sh" << 'GUARD_EOF'
#!/usr/bin/env bash
set -uo pipefail
CURRENT_STEP="${CURRENT_STEP:-warning-fix}"
LAST_INJECTED_STEP_VALUE="${LAST_INJECTED_STEP_VALUE:-}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"
_cur_step="$CURRENT_STEP"
if [[ -n "$_cur_step" && "$LAST_INJECTED_STEP_VALUE" != "$_cur_step" ]]; then
  echo "inject_next_workflow called" >> "$CALLS_LOG"
else
  echo "inject_skipped_duplicate step=${_cur_step}" >> "$CALLS_LOG"
  echo "run_merge_gate called" >> "$CALLS_LOG"
fi
exit 0
GUARD_EOF
  chmod +x "$SANDBOX/scripts/polling-guard.sh"

  CURRENT_STEP="warning-fix" \
  LAST_INJECTED_STEP_VALUE="" \
    run bash "$SANDBOX/scripts/polling-guard.sh"

  assert_success
  grep -q "inject_next_workflow called" "$CALLS_LOG"
  ! grep -q "run_merge_gate called" "$CALLS_LOG" 2>/dev/null
}

@test "issue-744[(b)]: 重複 inject 防止 — inject 成功後 LAST_INJECTED_STEP が current_step に更新される" {
  # inject 成功時に LAST_INJECTED_STEP を更新するロジックを再現
  cat > "$SANDBOX/scripts/inject-and-track.sh" << 'TRACK_EOF'
#!/usr/bin/env bash
set -uo pipefail
CURRENT_STEP="${CURRENT_STEP:-warning-fix}"
LAST_INJECTED_STEP_VALUE="${LAST_INJECTED_STEP_VALUE:-}"
INJECT_EXIT="${INJECT_EXIT:-0}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"
_cur_step="$CURRENT_STEP"
if [[ -n "$_cur_step" && "$LAST_INJECTED_STEP_VALUE" != "$_cur_step" ]]; then
  if [[ "$INJECT_EXIT" -eq 0 ]]; then
    LAST_INJECTED_STEP_VALUE="$_cur_step"
    echo "last_injected_step_updated=$_cur_step" >> "$CALLS_LOG"
  fi
fi
echo "final_last_injected=$LAST_INJECTED_STEP_VALUE"
exit 0
TRACK_EOF
  chmod +x "$SANDBOX/scripts/inject-and-track.sh"

  CURRENT_STEP="warning-fix" \
  LAST_INJECTED_STEP_VALUE="" \
  INJECT_EXIT=0 \
    run bash "$SANDBOX/scripts/inject-and-track.sh"

  assert_success
  assert_output --partial "final_last_injected=warning-fix"
  grep -q "last_injected_step_updated=warning-fix" "$CALLS_LOG"
}

# ===========================================================================
# Scenario (c): timeout 上限超過で status=failed と cleanup_worker が呼ばれる
# WHEN DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2、inject timeout を 3 回繰り返す
# THEN state に status=failed と failure.reason=inject_exhausted_pr_merge が書かれ、
#      cleanup_worker が呼ばれる
# ===========================================================================

@test "issue-744[(c)]: timeout 上限超過 — exit code 2（force-exit）で終了する" {
  # DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 の場合、3回目（count=3 > max=2）で force-exit
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=2 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  # exit code 2 = force-exit（上限超過）
  [[ "$status" -eq 2 ]]
}

@test "issue-744[(c)]: timeout 上限超過 — state に status=failed が書かれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=2 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  [[ "$status" -eq 2 ]]
  grep -q "state_write status=failed" "$STATE_FILE"
}

@test "issue-744[(c)]: timeout 上限超過 — state に failure.reason=inject_exhausted_pr_merge が書かれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=2 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  [[ "$status" -eq 2 ]]
  grep -q "state_write failure.reason=inject_exhausted_pr_merge" "$STATE_FILE"
}

@test "issue-744[(c)]: timeout 上限超過 — cleanup_worker が呼ばれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=2 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  [[ "$status" -eq 2 ]]
  grep -q "cleanup_worker called issue=744" "$CALLS_LOG"
}

@test "issue-744[(c)]: timeout 上限超過 — ERROR ログに count と max が含まれる" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=2 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  [[ "$status" -eq 2 ]]
  assert_output --partial "inject timeout 上限超過"
  assert_output --partial "count=3"
  assert_output --partial "max=2"
}

@test "issue-744[(c)]: timeout 上限超過 — trace log に category=INJECT_EXHAUSTED が記録される" {
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=2 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  [[ "$status" -eq 2 ]]
  grep -q "category=INJECT_EXHAUSTED" "$TRACE_LOG"
}

@test "issue-744[(c)]: timeout 上限未超過 — count=max 時点では force-exit しない" {
  # max=2、count=2（累計）: 2 > 2 は false なので force-exit しない
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=1 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  # exit 1（通常の timeout）、exit 2（force-exit）ではない
  [[ "$status" -eq 1 ]]
  ! grep -q "cleanup_worker called" "$CALLS_LOG" 2>/dev/null
}

@test "issue-744[(c)]: timeout 上限超過 — DEV_AUTOPILOT_INJECT_TIMEOUT_MAX デフォルト=5 が適用される" {
  # デフォルト max=5 の場合: count=5 → 5 > 5 は false、count=6 → 6 > 5 で force-exit
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=5 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  [[ "$status" -eq 2 ]]
  grep -q "cleanup_worker called issue=744" "$CALLS_LOG"
}

@test "issue-744[(c)]: inject 成功時は INJECT_TIMEOUT_COUNT をリセットする" {
  # INJECT_TIMEOUT_COUNT_INIT=3 で inject が成功した場合、カウンタが 0 にリセットされる
  # dispatch スクリプトはファイルでカウンタを管理するため、実行後にファイル内容を検証する
  NEXT_WORKFLOW="/twl:workflow-pr-merge" \
  SESSION_STATE="input-waiting" \
  INJECT_TIMEOUT_COUNT_INIT=3 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=5 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  # カウンタファイルが 0 にリセットされていること
  local count_file
  count_file=$(ls "$SANDBOX"/inject-timeout-count-* 2>/dev/null | head -1)
  [[ -n "$count_file" ]]
  local count_val
  count_val=$(cat "$count_file")
  [[ "$count_val" -eq 0 ]]
}

# ===========================================================================
# Edge cases: pr-merge 以外の通常 inject との共存確認
# ===========================================================================

@test "issue-744[edge]: /twl:workflow-pr-verify は通常通り inject される（pr-merge 修正の副作用なし）" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_success
  grep -q "tmux send-keys -t ap-#744 /twl:workflow-pr-verify" "$CALLS_LOG"
  grep -q "category=INJECT_SUCCESS" "$TRACE_LOG"
}

@test "issue-744[edge]: INJECT_TIMEOUT_COUNT は pr-merge 以外のタイムアウトでもインクリメントされる" {
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
  INJECT_TIMEOUT_COUNT_INIT=0 \
  DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=5 \
    run bash "$SANDBOX/scripts/pr-merge-744-dispatch.sh" "744" "ap-#744" "_default:744"

  assert_failure
  grep -q "category=INJECT_TIMEOUT" "$TRACE_LOG"
}
