#!/usr/bin/env bats
# inject-next-workflow-direct.bats
# Issue #720: inject_next_workflow() を lib/inject-next-workflow.sh から直接ソースして検証。
# dispatch double を使用せず、本体実装を直接テストすることでテストカバレッジの欠陥を補完する。
#
# テスト観点（dispatch double では検証不能だった項目）:
#   1. resolve_next_workflow が --issue フラグ付きで呼ばれること
#   2. RESOLVE_NOT_READY (exit=1): WARNING 非出力・trace 記録
#   3. RESOLVE_ERROR (exit=2): WARNING 出力・trace 記録
#   4. USE_SESSION_STATE=true 時に session-state wait が正しい引数で呼ばれること
#   5. inject 成功: tmux send-keys の skill 引数・INJECT_SUCCESS trace
#   6. inject タイムアウト: INJECT_TIMEOUT trace
#   7. pr-merge inject 時 status≠merge-ready で WARNING（#744 AC-4）

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: 外部コマンドスタブ + inject_next_workflow 本体をロード
# ---------------------------------------------------------------------------

setup() {
  common_setup

  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
  export AUTOPILOT_STAGNATE_SEC=3600
  mkdir -p "$SANDBOX/.autopilot/trace"

  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG

  # python3 stub: resolve_next_workflow / state read / state write を処理
  cat > "$STUB_BIN/python3" << 'STUB_EOF'
#!/usr/bin/env bash
_args="$*"
echo "python3 ${_args}" >> "${CALLS_LOG:-/dev/null}"
case "$_args" in
  *"resolve_next_workflow"*)
    _exit="${RESOLVE_EXIT:-0}"
    [[ "$_exit" -eq 0 ]] && echo "${NEXT_WORKFLOW:-/twl:workflow-pr-verify}"
    exit "$_exit"
    ;;
  *"state"*"read"*"status"*)
    echo "${STATE_STATUS:-running}"
    exit 0
    ;;
  *"state"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUB_EOF
  chmod +x "$STUB_BIN/python3"

  # tmux stub: capture-pane はプロンプト出力、send-keys はログ記録
  cat > "$STUB_BIN/tmux" << 'STUB_EOF'
#!/usr/bin/env bash
echo "tmux $*" >> "${CALLS_LOG:-/dev/null}"
case "$1" in
  capture-pane)
    printf '%s\n' "${PANE_OUTPUT:-> }"
    ;;
  send-keys)
    exit 0
    ;;
esac
STUB_EOF
  chmod +x "$STUB_BIN/tmux"

  # session-state スタブ（USE_SESSION_STATE=true 時に使用）
  _SS_CMD="$SANDBOX/session-state-stub.sh"
  cat > "$_SS_CMD" << 'STUB_EOF'
#!/usr/bin/env bash
echo "session-state $*" >> "${CALLS_LOG:-/dev/null}"
exit "${SESSION_STATE_EXIT:-0}"
STUB_EOF
  chmod +x "$_SS_CMD"
  export SESSION_STATE_CMD="$_SS_CMD" USE_SESSION_STATE=true

  # cleanup_worker スタブ（force-exit パス向け）
  cleanup_worker() { echo "cleanup_worker $*" >> "${CALLS_LOG:-/dev/null}"; }

  # 本体関数をロード（dispatch double ではなく実装を直接使用）
  # shellcheck source=../../../scripts/lib/inject-next-workflow.sh
  source "$REPO_ROOT/scripts/lib/inject-next-workflow.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: 当日の trace ログパスを返す
# ---------------------------------------------------------------------------
trace_log() {
  echo "$SANDBOX/.autopilot/trace/inject-$(date -u +%Y%m%d).log"
}

# ===========================================================================
# Scenario 1: resolve_next_workflow の呼び出し引数検証
# WHEN inject_next_workflow が呼ばれる
# THEN python3 -m twl.autopilot.resolve_next_workflow --issue <N> が実行される
# ===========================================================================

@test "direct[resolve_called]: resolve_next_workflow は --issue 引数付きで呼ばれる" {
  USE_SESSION_STATE=false PANE_OUTPUT="> " RESOLVE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" || true

  run grep "resolve_next_workflow.*--issue.*720" "$CALLS_LOG"
  assert_success
}

# ===========================================================================
# Scenario 2: RESOLVE_NOT_READY (exit=1) — WARNING なし・trace 記録
# ===========================================================================

@test "direct[RESOLVE_NOT_READY]: exit=1 時に stderr に WARNING を出力しない" {
  RESOLVE_EXIT=1 inject_next_workflow "720" "ap-#720" 2>"$SANDBOX/stderr.log" || true

  run grep "WARNING" "$SANDBOX/stderr.log"
  assert_failure
}

@test "direct[RESOLVE_NOT_READY]: exit=1 時に trace ログに RESOLVE_NOT_READY が記録される" {
  RESOLVE_EXIT=1 inject_next_workflow "720" "ap-#720" 2>/dev/null || true

  run grep "category=RESOLVE_NOT_READY" "$(trace_log)"
  assert_success
}

# ===========================================================================
# Scenario 3: RESOLVE_ERROR (exit=2) — WARNING 出力・trace 記録
# ===========================================================================

@test "direct[RESOLVE_ERROR]: exit=2 時に stderr に WARNING を出力する" {
  RESOLVE_EXIT=2 inject_next_workflow "720" "ap-#720" 2>"$SANDBOX/stderr.log" || true

  run grep "WARNING" "$SANDBOX/stderr.log"
  assert_success
}

@test "direct[RESOLVE_ERROR]: exit=2 時に trace ログに RESOLVE_ERROR が記録される" {
  RESOLVE_EXIT=2 inject_next_workflow "720" "ap-#720" 2>/dev/null || true

  run grep "category=RESOLVE_ERROR" "$(trace_log)"
  assert_success
}

# ===========================================================================
# Scenario 4: session-state wait 呼び出し検証（USE_SESSION_STATE=true）
# WHEN USE_SESSION_STATE=true で inject_next_workflow が呼ばれる
# THEN session-state wait <window_name> input-waiting --timeout 30 が実行される
# ===========================================================================

@test "direct[session-state]: USE_SESSION_STATE=true 時に session-state wait を window 名付きで呼ぶ" {
  RESOLVE_EXIT=0 SESSION_STATE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" 2>/dev/null || true

  run grep "session-state wait ap-#720" "$CALLS_LOG"
  assert_success
}

@test "direct[session-state]: session-state wait に input-waiting と --timeout が渡される" {
  RESOLVE_EXIT=0 SESSION_STATE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" 2>/dev/null || true

  run grep "session-state wait ap-#720 input-waiting --timeout" "$CALLS_LOG"
  assert_success
}

# ===========================================================================
# Scenario 5: inject 成功
# WHEN session-state が input-waiting を検出する（exit=0）
# THEN tmux send-keys に正しい skill が渡され、INJECT_SUCCESS が trace に記録される
# ===========================================================================

@test "direct[inject-success]: inject 成功時に tmux send-keys に skill 名が渡される" {
  RESOLVE_EXIT=0 NEXT_WORKFLOW="/twl:workflow-pr-verify" SESSION_STATE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" 2>/dev/null

  run grep "tmux send-keys.*workflow-pr-verify" "$CALLS_LOG"
  assert_success
}

@test "direct[inject-success]: inject 成功時に trace ログに INJECT_SUCCESS が記録される" {
  RESOLVE_EXIT=0 NEXT_WORKFLOW="/twl:workflow-pr-verify" SESSION_STATE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" 2>/dev/null

  run grep "category=INJECT_SUCCESS" "$(trace_log)"
  assert_success
}

@test "direct[inject-success]: inject 成功時に INJECT_SUCCESS trace に skill 名が含まれる" {
  RESOLVE_EXIT=0 NEXT_WORKFLOW="/twl:workflow-pr-verify" SESSION_STATE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" 2>/dev/null

  run grep "category=INJECT_SUCCESS.*skill=/twl:workflow-pr-verify" "$(trace_log)"
  assert_success
}

# ===========================================================================
# Scenario 6: inject タイムアウト（session-state が失敗）
# WHEN session-state が input-waiting を検出しない（exit=1）
# THEN inject_next_workflow は 1 を返し、INJECT_TIMEOUT が trace に記録される
# ===========================================================================

@test "direct[inject-timeout]: session-state タイムアウト時に exit code 1 を返す" {
  RESOLVE_EXIT=0 SESSION_STATE_EXIT=1 \
    run inject_next_workflow "720" "ap-#720"

  assert_failure
}

@test "direct[inject-timeout]: session-state タイムアウト時に INJECT_TIMEOUT が trace に記録される" {
  RESOLVE_EXIT=0 SESSION_STATE_EXIT=1 \
    inject_next_workflow "720" "ap-#720" 2>/dev/null || true

  run grep "category=INJECT_TIMEOUT" "$(trace_log)"
  assert_success
}

# ===========================================================================
# Scenario 7: pr-merge inject 時の status 検証 — WARNING（#744 AC-4）
# WHEN resolve が /twl:workflow-pr-merge を返し、status が merge-ready でない
# THEN stderr に WARNING が出力される（inject 自体は継続）
# ===========================================================================

@test "direct[pr-merge-warn]: status≠merge-ready 時に WARNING を出力する（#744 AC-4）" {
  RESOLVE_EXIT=0 NEXT_WORKFLOW="/twl:workflow-pr-merge" STATE_STATUS="running" \
  SESSION_STATE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" 2>"$SANDBOX/stderr.log" || true

  run grep "WARNING.*pr-merge inject" "$SANDBOX/stderr.log"
  assert_success
}

@test "direct[pr-merge-warn]: status=merge-ready 時は pr-merge WARNING を出力しない" {
  RESOLVE_EXIT=0 NEXT_WORKFLOW="/twl:workflow-pr-merge" STATE_STATUS="merge-ready" \
  SESSION_STATE_EXIT=0 \
    inject_next_workflow "720" "ap-#720" 2>"$SANDBOX/stderr.log" || true

  run grep "WARNING.*pr-merge inject" "$SANDBOX/stderr.log"
  assert_failure
}
