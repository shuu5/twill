#!/usr/bin/env bats
# inject-next-workflow-issue-707.bats
# Issue #707: orchestrator resolve_next_workflow 連続失敗 + inject タイムアウト修正
# Spec: deltaspec/changes/issue-707/specs/orchestrator-inject.md
#
# カバー範囲（9 Scenarios）:
#   1. RESOLVE_NOT_READY: non-terminal step で exit=1 → TRACE のみ、WARNING 出力なし
#   2. RESOLVE_ERROR: 予期せぬ exit code (exit=2, exit=127) → WARNING + TRACE
#   3. input-waiting 検出: session-state.sh state → input-waiting で inject 実行
#   4. processing 中: input-waiting でない → exponential backoff リトライ
#   5. exponential backoff: 2s, 4s, 8s スリープ順序
#   6. タイムアウト: 3回失敗 → INJECT_TIMEOUT trace
#   7. RESOLVE_NOT_READY trace ログ記録
#   8. INJECT_SUCCESS trace ログ記録
#   9. INJECT_TIMEOUT trace ログ記録
#
# テスト double 方針:
#   本ファイルでは autopilot-orchestrator.sh の inject_next_workflow() を
#   直接ソースするのではなく、修正後の振る舞いを仕様として表現した
#   dispatch スクリプト（inject-707-dispatch.sh）を sandbox 内で生成して検証する。
#   これにより実装前（TDD）でもテストが定義可能となる。
#
# 環境変数（dispatch スクリプト制御用）:
#   RESOLVE_EXIT    - resolve_next_workflow の終了コード（0=成功, 1=non-terminal, 2+=unexpected error）
#   NEXT_WORKFLOW   - resolve_next_workflow の返す skill 名
#   SESSION_STATE   - session-state.sh state が返す状態文字列（デフォルト: "input-waiting"）
#                     カンマ区切りで呼び出し順に指定可能
#                     例: "processing,processing,input-waiting"
#   SLEEP_LOG       - sleep コマンドの引数を記録するファイルパス
#   TRACE_LOG       - trace ログファイルパス（デフォルト: $SANDBOX/.autopilot/trace/inject-test.log）

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: inject_next_workflow() の修正後振る舞いを再現する test double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  SLEEP_LOG="$SANDBOX/sleep.log"
  TRACE_LOG="$SANDBOX/.autopilot/trace/inject-test.log"
  mkdir -p "$SANDBOX/.autopilot/trace"
  export CALLS_LOG SLEEP_LOG TRACE_LOG

  # inject-707-dispatch.sh: inject_next_workflow() の修正後振る舞いを再現
  # Issue #707 の修正仕様:
  #   - resolve exit=1  → TRACE (category=RESOLVE_NOT_READY), WARNING なし
  #   - resolve exit!=0 かつ !=1 → WARNING + TRACE (category=RESOLVE_ERROR)
  #   - input-waiting 検出: session-state.sh state <window> の出力で判定
  #   - exponential backoff: 1回目=2s, 2回目=4s, 3回目=8s
  #   - 3回全失敗 → TRACE (category=INJECT_TIMEOUT)
  #   - inject 成功 → TRACE (category=INJECT_SUCCESS)
  cat > "$SANDBOX/scripts/inject-707-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# inject-707-dispatch.sh
# inject_next_workflow() の修正後振る舞いを再現するテスト double (Issue #707)
set -uo pipefail

issue="$1"
window_name="$2"

RESOLVE_EXIT="${RESOLVE_EXIT:-0}"
NEXT_WORKFLOW="${NEXT_WORKFLOW:-/twl:workflow-pr-verify}"
SESSION_STATE="${SESSION_STATE:-input-waiting}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"
SLEEP_LOG="${SLEEP_LOG:-/dev/null}"
TRACE_LOG="${TRACE_LOG:-/dev/null}"

trace_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- session-state スタブ: SESSION_STATE をカンマ区切りで順次消費 ---
# STATE_CALL_COUNT を共有ファイルで管理
STATE_CALL_FILE="${SANDBOX:-/tmp}/state-call-count"
echo "0" > "$STATE_CALL_FILE"

get_next_state() {
  local count
  count=$(cat "$STATE_CALL_FILE" 2>/dev/null || echo 0)
  local idx=$((count))
  local state_entry
  IFS=',' read -ra _states <<< "$SESSION_STATE"
  local len="${#_states[@]}"
  if (( idx < len )); then
    state_entry="${_states[$idx]}"
  else
    # 最後のエントリを繰り返す
    state_entry="${_states[$((len - 1))]}"
  fi
  echo $(( count + 1 )) > "$STATE_CALL_FILE"
  echo "$state_entry"
}

# --- resolve_next_workflow 呼び出し記録 ---
echo "resolve_next_workflow --issue $issue exit=$RESOLVE_EXIT" >> "$CALLS_LOG"

# --- exit=1: non-terminal step (RESOLVE_NOT_READY) ---
if [[ "$RESOLVE_EXIT" -eq 1 ]]; then
  echo "[${trace_ts}] issue=${issue} category=RESOLVE_NOT_READY result=skip reason=\"non-terminal step\"" >> "$TRACE_LOG"
  # WARNING は出力しない（TRACE のみ）
  exit 1
fi

# --- exit!=0 かつ !=1: 予期せぬエラー (RESOLVE_ERROR) ---
if [[ "$RESOLVE_EXIT" -ne 0 ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 予期せぬエラー — exit=${RESOLVE_EXIT}" >&2
  echo "[${trace_ts}] issue=${issue} category=RESOLVE_ERROR result=skip reason=\"unexpected exit=${RESOLVE_EXIT}\"" >> "$TRACE_LOG"
  exit 1
fi

# --- resolve 成功: skill バリデーション ---
_skill_safe="${NEXT_WORKFLOW//$'\n'/}"
if [[ ! "$_skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]] && \
   [[ "$_skill_safe" != "pr-merge" ]] && \
   [[ "$_skill_safe" != "/twl:workflow-pr-merge" ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: 不正な workflow skill '${_skill_safe:0:200}'" >&2
  exit 1
fi

# --- input-waiting 検出: exponential backoff (2s, 4s, 8s) ---
backoff_waits=(2 4 8)
inject_done=0

for _i in 0 1 2; do
  current_state=$(get_next_state)
  echo "session-state state $window_name -> $current_state" >> "$CALLS_LOG"

  if [[ "$current_state" == "input-waiting" ]]; then
    inject_done=1
    break
  fi

  wait_sec="${backoff_waits[$_i]}"
  echo "sleep $wait_sec" >> "$SLEEP_LOG"
  # 実際の sleep は短縮（テスト高速化）
  # sleep 0.001
done

# --- タイムアウト判定 ---
if [[ "$inject_done" -eq 0 ]]; then
  echo "[${trace_ts}] issue=${issue} skill=${_skill_safe} category=INJECT_TIMEOUT result=timeout" >> "$TRACE_LOG"
  exit 1
fi

# --- inject 実行 ---
echo "tmux send-keys -t $window_name $_skill_safe" >> "$CALLS_LOG"
_inject_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[${_inject_ts}] issue=${issue} skill=${_skill_safe} category=INJECT_SUCCESS result=success" >> "$TRACE_LOG"

exit 0
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/inject-707-dispatch.sh"

  # SANDBOX 変数を dispatch スクリプト内から参照できるよう export
  export SANDBOX
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: resolve ログレベル分離
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario 1: RESOLVE_NOT_READY — non-terminal step で exit=1
# WHEN resolve_next_workflow が exit=1 で終了する
# THEN TRACE ログに category=RESOLVE_NOT_READY として記録され、WARNING は出力されない
# ---------------------------------------------------------------------------

@test "issue-707[RESOLVE_NOT_READY]: exit=1 時に WARNING を出力しない" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  # WARNING が stderr に出力されていないことを確認
  refute_output --partial "WARNING"
}

@test "issue-707[RESOLVE_NOT_READY]: exit=1 時に trace ログに category=RESOLVE_NOT_READY を記録する" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "category=RESOLVE_NOT_READY" "$TRACE_LOG"
}

@test "issue-707[RESOLVE_NOT_READY]: exit=1 時に TRACE ログに issue 番号が含まれる" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "issue=707" "$TRACE_LOG"
}

# ---------------------------------------------------------------------------
# Scenario 2: RESOLVE_ERROR — 予期せぬ exit code
# WHEN resolve_next_workflow が exit=2 または exit=127 で終了する
# THEN WARNING ログに「resolve_next_workflow 予期せぬエラー」が出力され、
#      TRACE ログに category=RESOLVE_ERROR として記録される
# ---------------------------------------------------------------------------

@test "issue-707[RESOLVE_ERROR]: exit=2 時に WARNING ログを出力する" {
  RESOLVE_EXIT=2 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  assert_output --partial "WARNING"
  assert_output --partial "resolve_next_workflow 予期せぬエラー"
}

@test "issue-707[RESOLVE_ERROR]: exit=2 時に trace ログに category=RESOLVE_ERROR を記録する" {
  RESOLVE_EXIT=2 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "category=RESOLVE_ERROR" "$TRACE_LOG"
}

@test "issue-707[RESOLVE_ERROR]: exit=127 時に WARNING ログを出力する（コマンド未発見相当）" {
  RESOLVE_EXIT=127 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  assert_output --partial "WARNING"
  assert_output --partial "resolve_next_workflow 予期せぬエラー"
}

@test "issue-707[RESOLVE_ERROR]: exit=127 時に trace ログに category=RESOLVE_ERROR を記録する" {
  RESOLVE_EXIT=127 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "category=RESOLVE_ERROR" "$TRACE_LOG"
}

@test "issue-707[RESOLVE_ERROR]: RESOLVE_ERROR ログに exit code が含まれる" {
  RESOLVE_EXIT=2 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "exit=2" "$TRACE_LOG"
}

# exit=1 は RESOLVE_NOT_READY であり RESOLVE_ERROR ではないことを確認
@test "issue-707[RESOLVE_NOT_READY vs RESOLVE_ERROR]: exit=1 は RESOLVE_ERROR を記録しない" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  ! grep -q "category=RESOLVE_ERROR" "$TRACE_LOG" 2>/dev/null
}

@test "issue-707[RESOLVE_NOT_READY vs RESOLVE_ERROR]: exit=2 は RESOLVE_NOT_READY を記録しない" {
  RESOLVE_EXIT=2 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  ! grep -q "category=RESOLVE_NOT_READY" "$TRACE_LOG" 2>/dev/null
}

# ===========================================================================
# Requirement: session-state.sh ベースの input-waiting 検出
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario 3: Worker が terminal step で input-waiting 状態
# WHEN session-state.sh state <window> が input-waiting を返す
# THEN inject が実行され、trace ログに category=INJECT_SUCCESS が記録される
# ---------------------------------------------------------------------------

@test "issue-707[input-waiting]: input-waiting 検出時に inject を実行する" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

@test "issue-707[input-waiting]: input-waiting 検出時に trace ログに category=INJECT_SUCCESS を記録する" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  grep -q "category=INJECT_SUCCESS" "$TRACE_LOG"
}

@test "issue-707[input-waiting]: session-state.sh state が呼ばれていることを確認する" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  grep -q "session-state state ap-#707" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Scenario 4: Worker がまだ processing 中
# WHEN session-state.sh state が processing を返す（input-waiting ではない）
# THEN exponential backoff で最大3回リトライし、全失敗時に INJECT_TIMEOUT を記録する
# ---------------------------------------------------------------------------

@test "issue-707[processing]: processing 状態が続く場合に inject を実行しない" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  ! grep -q "tmux send-keys" "$CALLS_LOG" 2>/dev/null
}

@test "issue-707[processing]: processing が3回続く場合に trace ログに category=INJECT_TIMEOUT を記録する" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "category=INJECT_TIMEOUT" "$TRACE_LOG"
}

@test "issue-707[processing]: processing 状態で3回 session-state を呼び出す" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  local count
  count=$(grep -c "session-state state ap-#707" "$CALLS_LOG" 2>/dev/null || echo 0)
  [[ "$count" -eq 3 ]]
}

# ===========================================================================
# Requirement: prompt 検出 exponential backoff
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario 5: exponential backoff — 2s, 4s, 8s スリープ順序
# WHEN 3回全ての session-state チェックが実行される
# THEN sleep 引数が 2, 4, 8 の順で記録される
# ---------------------------------------------------------------------------

@test "issue-707[exponential-backoff]: 1回目のスリープが 2 秒である" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  local first_sleep
  first_sleep=$(head -1 "$SLEEP_LOG" 2>/dev/null || echo "")
  [[ "$first_sleep" == "sleep 2" ]]
}

@test "issue-707[exponential-backoff]: 2回目のスリープが 4 秒である" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  local second_sleep
  second_sleep=$(sed -n '2p' "$SLEEP_LOG" 2>/dev/null || echo "")
  [[ "$second_sleep" == "sleep 4" ]]
}

@test "issue-707[exponential-backoff]: 3回目のスリープが 8 秒である" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  local third_sleep
  third_sleep=$(sed -n '3p' "$SLEEP_LOG" 2>/dev/null || echo "")
  [[ "$third_sleep" == "sleep 8" ]]
}

@test "issue-707[exponential-backoff]: 合計スリープは 2+4+8=14 秒分（3エントリ）記録される" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  local sleep_count
  sleep_count=$(wc -l < "$SLEEP_LOG" 2>/dev/null || echo 0)
  [[ "$sleep_count" -eq 3 ]]
}

# ---------------------------------------------------------------------------
# Scenario: 1回目のリトライで input-waiting 検出
# WHEN 1回目の session-state チェックで input-waiting が返る
# THEN inject が実行される（2s 待機後）
# ---------------------------------------------------------------------------

@test "issue-707[exponential-backoff]: 1回目リトライで input-waiting 検出時に inject を実行する" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

@test "issue-707[exponential-backoff]: 1回目で検出した場合はスリープが記録されない" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  local sleep_count
  sleep_count=$(wc -l < "$SLEEP_LOG" 2>/dev/null || echo 0)
  [[ "$sleep_count" -eq 0 ]]
}

@test "issue-707[exponential-backoff]: 2回目で検出した場合の最初のスリープが 2 秒である" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing,input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  local first_sleep
  first_sleep=$(head -1 "$SLEEP_LOG" 2>/dev/null || echo "")
  [[ "$first_sleep" == "sleep 2" ]]
}

# ---------------------------------------------------------------------------
# Scenario: 2回目のリトライで input-waiting 検出（processing → input-waiting）
# ---------------------------------------------------------------------------

@test "issue-707[exponential-backoff]: 2回目リトライで input-waiting 検出時に inject を実行する" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing,input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  grep -q "tmux send-keys" "$CALLS_LOG"
}

@test "issue-707[exponential-backoff]: 2回目で検出した場合にスリープが 1 回記録される（2s）" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing,input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  local sleep_count
  sleep_count=$(wc -l < "$SLEEP_LOG" 2>/dev/null || echo 0)
  [[ "$sleep_count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Scenario 6: タイムアウト — 3回失敗 → INJECT_TIMEOUT trace
# WHEN 3回全ての session-state チェックで input-waiting が返らない
# THEN inject_next_workflow は 1 を返し、trace に category=INJECT_TIMEOUT が記録される
# ---------------------------------------------------------------------------

@test "issue-707[INJECT_TIMEOUT]: 3回全失敗時に exit code 1 を返す" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing,processing,processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
}

@test "issue-707[INJECT_TIMEOUT]: 3回全失敗時に INJECT_TIMEOUT を trace に記録する" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing,processing,processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "category=INJECT_TIMEOUT" "$TRACE_LOG"
}

@test "issue-707[INJECT_TIMEOUT]: idle 状態（processing 以外）でも input-waiting でなければタイムアウトとなる" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="idle,idle,idle" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -q "category=INJECT_TIMEOUT" "$TRACE_LOG"
}

# ===========================================================================
# Requirement: trace ログカテゴリ記録
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario 7: trace ログに RESOLVE_NOT_READY カテゴリが記録される
# WHEN resolve_next_workflow が exit=1 で終了する
# THEN trace ログに category=RESOLVE_NOT_READY を含むエントリが追記される
# ---------------------------------------------------------------------------

@test "issue-707[trace-RESOLVE_NOT_READY]: trace ログファイルに RESOLVE_NOT_READY エントリが追記される" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  [[ -f "$TRACE_LOG" ]]
  grep -q "category=RESOLVE_NOT_READY" "$TRACE_LOG"
}

@test "issue-707[trace-RESOLVE_NOT_READY]: RESOLVE_NOT_READY エントリに issue 番号が含まれる" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep "category=RESOLVE_NOT_READY" "$TRACE_LOG" | grep -q "issue=707"
}

@test "issue-707[trace-RESOLVE_NOT_READY]: RESOLVE_NOT_READY エントリが ISO8601 タイムスタンプを含む" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep -qE "^\[20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]" "$TRACE_LOG"
}

# ---------------------------------------------------------------------------
# Scenario 8: trace ログに INJECT_SUCCESS カテゴリが記録される
# WHEN inject が成功する（tmux send-keys が正常終了）
# THEN trace ログに category=INJECT_SUCCESS を含むエントリが追記される
# ---------------------------------------------------------------------------

@test "issue-707[trace-INJECT_SUCCESS]: trace ログファイルに INJECT_SUCCESS エントリが追記される" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  [[ -f "$TRACE_LOG" ]]
  grep -q "category=INJECT_SUCCESS" "$TRACE_LOG"
}

@test "issue-707[trace-INJECT_SUCCESS]: INJECT_SUCCESS エントリに skill 名が含まれる" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  grep "category=INJECT_SUCCESS" "$TRACE_LOG" | grep -q "skill=/twl:workflow-pr-verify"
}

@test "issue-707[trace-INJECT_SUCCESS]: INJECT_SUCCESS エントリに issue 番号が含まれる" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  grep "category=INJECT_SUCCESS" "$TRACE_LOG" | grep -q "issue=707"
}

# ---------------------------------------------------------------------------
# Scenario 9: trace ログに INJECT_TIMEOUT カテゴリが記録される
# WHEN 3回全ての input-waiting チェックが失敗する
# THEN trace ログに category=INJECT_TIMEOUT を含むエントリが追記される
# ---------------------------------------------------------------------------

@test "issue-707[trace-INJECT_TIMEOUT]: trace ログファイルに INJECT_TIMEOUT エントリが追記される" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  [[ -f "$TRACE_LOG" ]]
  grep -q "category=INJECT_TIMEOUT" "$TRACE_LOG"
}

@test "issue-707[trace-INJECT_TIMEOUT]: INJECT_TIMEOUT エントリに skill 名が含まれる" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep "category=INJECT_TIMEOUT" "$TRACE_LOG" | grep -q "skill=/twl:workflow-pr-verify"
}

@test "issue-707[trace-INJECT_TIMEOUT]: INJECT_TIMEOUT エントリに issue 番号が含まれる" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  grep "category=INJECT_TIMEOUT" "$TRACE_LOG" | grep -q "issue=707"
}

# ===========================================================================
# Edge cases: 複合シナリオ
# ===========================================================================

# exit=1（RESOLVE_NOT_READY）は WARNING も INJECT_TIMEOUT も記録しない
@test "issue-707[edge]: exit=1 は INJECT_TIMEOUT を記録しない（ログカテゴリ混同防止）" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  ! grep -q "category=INJECT_TIMEOUT" "$TRACE_LOG" 2>/dev/null
  ! grep -q "category=INJECT_SUCCESS" "$TRACE_LOG" 2>/dev/null
}

# INJECT_SUCCESS と INJECT_TIMEOUT は同一 trace に共存しない（正常系）
@test "issue-707[edge]: inject 成功時に INJECT_TIMEOUT が記録されない" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_success
  ! grep -q "category=INJECT_TIMEOUT" "$TRACE_LOG" 2>/dev/null
}

# タイムアウト時に INJECT_SUCCESS が記録されない
@test "issue-707[edge]: タイムアウト時に INJECT_SUCCESS が記録されない" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-pr-verify" \
  SESSION_STATE="processing" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "707" "ap-#707"

  assert_failure
  ! grep -q "category=INJECT_SUCCESS" "$TRACE_LOG" 2>/dev/null
}

# 異なる issue 番号でも正しく動作する
@test "issue-707[edge]: issue 番号 100 で RESOLVE_NOT_READY が正常に記録される" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "100" "ap-#100"

  assert_failure
  grep -q "issue=100" "$TRACE_LOG"
  grep -q "category=RESOLVE_NOT_READY" "$TRACE_LOG"
  refute_output --partial "WARNING"
}

@test "issue-707[edge]: issue 番号 100 で INJECT_SUCCESS が正常に記録される" {
  RESOLVE_EXIT=0 \
  NEXT_WORKFLOW="/twl:workflow-spec-refine" \
  SESSION_STATE="input-waiting" \
    run bash "$SANDBOX/scripts/inject-707-dispatch.sh" "100" "ap-#100"

  assert_success
  grep -q "issue=100" "$TRACE_LOG"
  grep -q "category=INJECT_SUCCESS" "$TRACE_LOG"
}
