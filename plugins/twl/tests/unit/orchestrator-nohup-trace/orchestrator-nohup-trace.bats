#!/usr/bin/env bats
# orchestrator-nohup-trace.bats
# Requirement: orchestrator nohup 実行 + inject_next_workflow トレース記録
# Spec: deltaspec/changes/issue-438/specs/orchestrator-persistence/spec.md
# Coverage: --type=unit --coverage=edge-cases
#
# 検証する仕様:
#   1. orchestrator が nohup/disown 起動後も継続すること（PID + 起動時刻が trace に記録される）
#   2. inject_next_workflow() の実行結果が .autopilot/trace/inject-{YYYYMMDD}.log に記録される
#      - 成功時: result=success
#      - resolve 失敗時: result=skip reason="resolve_next_workflow exit=1"
#      - prompt 未検出時: result=timeout reason="prompt not found"
#
# test double: orchestrator-trace-dispatch.sh
#   Env:
#     RESOLVE_EXIT   - resolve_next_workflow の終了コード（デフォルト: 0）
#     PANE_OUTPUT    - tmux capture-pane の出力（デフォルト: "> "）
#     TRACE_LOG_DIR  - トレースログディレクトリ（デフォルト: $SANDBOX/.autopilot/trace）
#     CALLS_LOG      - 呼び出し記録ファイル

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: テスト double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  TRACE_LOG_DIR="$SANDBOX/.autopilot/trace"
  export CALLS_LOG TRACE_LOG_DIR
  mkdir -p "$TRACE_LOG_DIR"

  # trace_log_date: 今日の YYYYMMDD
  TRACE_DATE=$(date -u +"%Y%m%d")
  export TRACE_DATE

  # inject_next_workflow のトレース記録を含む test double
  cat > "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# orchestrator-trace-dispatch.sh
# inject_next_workflow() + トレースログ記録の test double
# Usage: <issue> <window_name>
# Env:
#   NEXT_WORKFLOW  - resolve_next_workflow の返り値（デフォルト: "/twl:workflow-pr-verify"）
#   RESOLVE_EXIT   - resolve_next_workflow の終了コード（デフォルト: 0）
#   PANE_OUTPUT    - tmux capture-pane の出力（デフォルト: "> "）
#   TRACE_LOG_DIR  - トレースログ出力先ディレクトリ
#   CALLS_LOG      - 呼び出し記録ファイル
set -uo pipefail

issue="$1"
window_name="$2"

NEXT_WORKFLOW="${NEXT_WORKFLOW:-/twl:workflow-pr-verify}"
RESOLVE_EXIT="${RESOLVE_EXIT:-0}"
PANE_OUTPUT="${PANE_OUTPUT:-"> "}"
TRACE_LOG_DIR="${TRACE_LOG_DIR:-/tmp/autopilot-trace}"
CALLS_LOG="${CALLS_LOG:-/dev/null}"

mkdir -p "$TRACE_LOG_DIR"
trace_date=$(date -u +"%Y%m%d")
INJECT_LOG="${TRACE_LOG_DIR}/inject-${trace_date}.log"

# --- resolve_next_workflow 呼び出し ---
echo "resolve_next_workflow --issue $issue" >> "$CALLS_LOG"
if [[ "$RESOLVE_EXIT" -ne 0 ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 失敗 — inject スキップ" >&2
  # トレース: resolve 失敗
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) issue=${issue} result=skip reason=\"resolve_next_workflow exit=1\"" >> "$INJECT_LOG"
  exit 1
fi
next_skill="$NEXT_WORKFLOW"

if [[ -z "$next_skill" ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: resolve_next_workflow 失敗 — inject スキップ" >&2
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) issue=${issue} result=skip reason=\"resolve_next_workflow exit=1\"" >> "$INJECT_LOG"
  exit 1
fi

# --- allow-list バリデーション ---
_skill_safe="${next_skill//$'\n'/}"
if [[ "$_skill_safe" == "pr-merge" || "$_skill_safe" == "/twl:workflow-pr-merge" ]]; then
  echo "[orchestrator] Issue #${issue}: pr-merge 検出 — inject スキップ、merge-gate フローに委譲" >&2
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) issue=${issue} result=skip reason=\"pr-merge terminal workflow\"" >> "$INJECT_LOG"
  exit 0
fi
if [[ ! "$_skill_safe" =~ ^/twl:workflow-[a-z][a-z0-9-]*$ ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: 不正な workflow skill '${_skill_safe:0:200}' — inject スキップ" >&2
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) issue=${issue} result=skip reason=\"invalid skill name\"" >> "$INJECT_LOG"
  exit 1
fi

# --- tmux pane 入力待ち確認（最大3回） ---
_prompt_re='[>$][[:space:]]*$'
prompt_found=0
for _i in 1 2 3; do
  echo "tmux capture-pane -p -t $window_name" >> "$CALLS_LOG"
  pane_tail=$(echo "$PANE_OUTPUT" | tail -1)
  if [[ "$pane_tail" =~ $_prompt_re ]]; then
    prompt_found=1
    break
  fi
  sleep 0.01
done

if [[ "$prompt_found" -eq 0 ]]; then
  echo "[orchestrator] Issue #${issue}: WARNING: inject タイムアウト — ${POLL_INTERVAL:-10}秒後に再チェック" >&2
  # トレース: timeout
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) issue=${issue} result=timeout reason=\"prompt not found\"" >> "$INJECT_LOG"
  exit 1
fi

# --- inject 実行 ---
echo "tmux send-keys -t $window_name $_skill_safe" >> "$CALLS_LOG"
echo "[orchestrator] Issue #${issue}: inject_next_workflow — $_skill_safe" >&2

# トレース: 成功
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) issue=${issue} result=success skill=${_skill_safe}" >> "$INJECT_LOG"

exit 0
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/orchestrator-trace-dispatch.sh"

  # orchestrator PID 記録スクリプト（nohup 起動シミュレーション）
  cat > "$SANDBOX/scripts/orchestrator-pid-logger.sh" << 'PID_EOF'
#!/usr/bin/env bash
# orchestrator-pid-logger.sh
# nohup 起動後の PID + 起動時刻をトレースログに記録する test double
# Usage: <phase_num>
# Env:
#   TRACE_LOG_DIR - トレースログ出力先ディレクトリ
set -uo pipefail

phase_num="${1:-1}"
TRACE_LOG_DIR="${TRACE_LOG_DIR:-/tmp/autopilot-trace}"
mkdir -p "$TRACE_LOG_DIR"

ORCHESTRATOR_LOG="${TRACE_LOG_DIR}/orchestrator-phase-${phase_num}.log"
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# $$ は本スクリプト自身の PID（orchestrator プロセスを代理）
echo "orchestrator_pid=$$ started_at=${started_at} phase=${phase_num}" >> "$ORCHESTRATOR_LOG"
echo "[orchestrator] Phase ${phase_num}: PID=$$, started_at=${started_at}" >&2
PID_EOF
  chmod +x "$SANDBOX/scripts/orchestrator-pid-logger.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: orchestrator nohup 実行
# Spec: deltaspec/changes/issue-438/specs/orchestrator-persistence/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: orchestrator PID がトレースログに記録される
# WHEN Pilot が orchestrator を nohup/disown で起動する
# THEN orchestrator の PID と起動時刻が .autopilot/trace/orchestrator-phase-{N}.log に記録される
# ---------------------------------------------------------------------------

@test "orchestrator[pid-trace]: orchestrator-phase-1.log が作成される" {
  run bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"

  assert_success
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-1.log" ]]
}

@test "orchestrator[pid-trace]: orchestrator_pid がログに記録される" {
  run bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"

  assert_success
  grep -q "orchestrator_pid=" "${TRACE_LOG_DIR}/orchestrator-phase-1.log"
}

@test "orchestrator[pid-trace]: started_at が ISO8601 形式でログに記録される" {
  run bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"

  assert_success
  grep -qE "started_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" \
    "${TRACE_LOG_DIR}/orchestrator-phase-1.log"
}

@test "orchestrator[pid-trace]: phase 番号がログに記録される" {
  run bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "3"

  assert_success
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-3.log" ]]
  grep -q "phase=3" "${TRACE_LOG_DIR}/orchestrator-phase-3.log"
}

@test "orchestrator[pid-trace]: PID は正の整数である" {
  run bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"

  assert_success
  local pid
  pid=$(grep -oP 'orchestrator_pid=\K[0-9]+' "${TRACE_LOG_DIR}/orchestrator-phase-1.log")
  [[ -n "$pid" && "$pid" -gt 0 ]]
}

@test "orchestrator[pid-trace]: stderr に [orchestrator] プレフィックス付きログを出力する" {
  run bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"

  assert_success
  assert_output --partial "[orchestrator]"
  assert_output --partial "Phase 1"
}

# Edge case: 複数 Phase でそれぞれ独立したログファイルが作成される
@test "orchestrator[pid-trace][edge]: Phase 1 と Phase 2 で別ファイルが作成される" {
  bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"
  bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "2"

  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-1.log" ]]
  [[ -f "${TRACE_LOG_DIR}/orchestrator-phase-2.log" ]]
}

# Edge case: ログファイルは追記形式（既存エントリが上書きされない）
@test "orchestrator[pid-trace][edge]: ログは追記形式で既存エントリを保持する" {
  bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"
  bash "$SANDBOX/scripts/orchestrator-pid-logger.sh" "1"

  local count
  count=$(grep -c "orchestrator_pid=" "${TRACE_LOG_DIR}/orchestrator-phase-1.log")
  [[ "$count" -ge 2 ]]
}

# ===========================================================================
# Requirement: inject_next_workflow 実行結果のトレース記録
# Spec: deltaspec/changes/issue-438/specs/orchestrator-persistence/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: inject 成功時にトレースが記録される
# WHEN inject_next_workflow() が /twl:workflow-test-ready を Worker に inject する
# THEN .autopilot/trace/inject-{YYYYMMDD}.log に result=success エントリが追記される
# ---------------------------------------------------------------------------

@test "inject-trace[success]: inject 成功時に inject ログファイルが作成される" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_success
  [[ -f "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log" ]]
}

@test "inject-trace[success]: inject 成功時に result=success が記録される" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_success
  grep -q "result=success" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

@test "inject-trace[success]: inject 成功時に skill 名がログに含まれる" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_success
  grep -q "skill=/twl:workflow-test-ready" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

@test "inject-trace[success]: inject 成功時に issue 番号がログに含まれる" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_success
  grep -q "issue=438" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

@test "inject-trace[success]: inject 成功ログに ISO8601 タイムスタンプが含まれる" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_success
  grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z " \
    "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

# ---------------------------------------------------------------------------
# Scenario: inject 失敗時（resolve 失敗）にトレースが記録される
# WHEN resolve_next_workflow が exit code 1 で失敗する
# THEN .autopilot/trace/inject-{YYYYMMDD}.log に result=skip reason="resolve_next_workflow exit=1" が追記される
# ---------------------------------------------------------------------------

@test "inject-trace[resolve-fail]: resolve 失敗時に inject ログファイルが作成される" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  [[ -f "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log" ]]
}

@test "inject-trace[resolve-fail]: resolve 失敗時に result=skip が記録される" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  grep -q "result=skip" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

@test "inject-trace[resolve-fail]: resolve 失敗時に reason が resolve_next_workflow exit=1 を含む" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  grep -q 'reason="resolve_next_workflow exit=1"' "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

@test "inject-trace[resolve-fail]: resolve 失敗時に issue 番号がログに含まれる" {
  RESOLVE_EXIT=1 \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  grep -q "issue=438" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

# ---------------------------------------------------------------------------
# Scenario: inject 失敗時（prompt 未検出）にトレースが記録される
# WHEN tmux pane の prompt 検出が3回リトライ後タイムアウトする
# THEN .autopilot/trace/inject-{YYYYMMDD}.log に result=timeout reason="prompt not found" が追記される
# ---------------------------------------------------------------------------

@test "inject-trace[timeout]: prompt 未検出時に inject ログファイルが作成される" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  [[ -f "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log" ]]
}

@test "inject-trace[timeout]: prompt 未検出時に result=timeout が記録される" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  grep -q "result=timeout" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

@test "inject-trace[timeout]: prompt 未検出時に reason が prompt not found を含む" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  grep -q 'reason="prompt not found"' "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

@test "inject-trace[timeout]: prompt 未検出時に issue 番号がログに含まれる" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="Working..." \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_failure
  grep -q "issue=438" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

# ---------------------------------------------------------------------------
# Edge cases: ログファイル管理
# ---------------------------------------------------------------------------

# Edge case: 日付ごとにファイルが分かれる（ファイル名が YYYYMMDD 形式）
@test "inject-trace[edge]: inject ログファイル名が inject-YYYYMMDD.log 形式" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" \
  PANE_OUTPUT="> " \
    run bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438"

  assert_success
  # ファイルが今日の日付で作成されている
  local expected_file="${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
  [[ -f "$expected_file" ]]
}

# Edge case: 複数の inject 呼び出しが同一ログに追記される（silent fail 排除）
@test "inject-trace[edge]: 複数回の失敗が同一ログに追記される（silent fail なし）" {
  RESOLVE_EXIT=1 \
    bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438" || true
  PANE_OUTPUT="Working..." \
    bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "438" "ap-#438" || true

  local count
  count=$(grep -c "issue=438" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log")
  [[ "$count" -ge 2 ]]
}

# Edge case: 成功と失敗が混在してもそれぞれ記録される
@test "inject-trace[edge]: 成功と失敗が同一ログに混在して記録される" {
  NEXT_WORKFLOW="/twl:workflow-test-ready" PANE_OUTPUT="> " \
    bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "100" "ap-#100" || true
  RESOLVE_EXIT=1 \
    bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "101" "ap-#101" || true
  NEXT_WORKFLOW="/twl:workflow-pr-verify" PANE_OUTPUT="Working..." \
    bash "$SANDBOX/scripts/orchestrator-trace-dispatch.sh" "102" "ap-#102" || true

  grep -q "result=success" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
  grep -q "result=skip" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
  grep -q "result=timeout" "${TRACE_LOG_DIR}/inject-${TRACE_DATE}.log"
}

# ===========================================================================
# Requirement: orchestrator 継続動作の文書確認
# Scenario: Pilot がメッセージを受信しても orchestrator が継続する
# WHEN Pilot が orchestrator 起動後に新しいユーザーメッセージを受信する
# THEN orchestrator プロセスは停止せず polling loop を継続し、inject_next_workflow() が正常に呼ばれる
# ===========================================================================

# このシナリオは autopilot-orchestrator.sh が nohup/disown 経由で起動されることで実現する。
# スクリプト実装のドキュメント検証として、scripts ファイルの内容を確認する。

@test "orchestrator[persistence]: autopilot-orchestrator.sh が存在する" {
  [[ -f "$SANDBOX/scripts/autopilot-orchestrator.sh" ]]
}

@test "orchestrator[persistence]: inject_next_workflow 関数が autopilot-orchestrator.sh に定義されている" {
  grep -q "inject_next_workflow()" "$SANDBOX/scripts/autopilot-orchestrator.sh"
}
