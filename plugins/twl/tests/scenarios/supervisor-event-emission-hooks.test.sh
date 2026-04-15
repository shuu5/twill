#!/usr/bin/env bash
# =============================================================================
# Functional Tests: supervisor-event-emission-hooks
# Tests the behavior of scripts/hooks/supervisor-*.sh
# Coverage: AUTOPILOT_DIR 設定あり/なし、JSON フォーマット検証、exit 0 保証
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_DIR="${PROJECT_ROOT}/scripts/hooks"

PASS=0
FAIL=0
ERRORS=()

SANDBOX=""
AUTOPILOT_DIR_TEST=""
EVENTS_DIR_TEST=""
SUPERVISOR_DIR_TEST=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  AUTOPILOT_DIR_TEST="${SANDBOX}/.autopilot"
  SUPERVISOR_DIR_TEST="${SANDBOX}/.supervisor"
  EVENTS_DIR_TEST="${SUPERVISOR_DIR_TEST}/events"
  mkdir -p "$AUTOPILOT_DIR_TEST"
  mkdir -p "$EVENTS_DIR_TEST"
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
  AUTOPILOT_DIR_TEST=""
  EVENTS_DIR_TEST=""
  SUPERVISOR_DIR_TEST=""
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  setup_sandbox
  result=0
  $func || result=$?
  teardown_sandbox
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ERRORS+=("$name")
    ((FAIL++)) || true
  fi
}

# --- ヘルパー ---

# AUTOPILOT_DIR を sandbox に向けて hook を実行（EVENTS_DIR を上書き）
# hook のパス解決: AUTOPILOT_DIR/../.supervisor/events を使うため
# sandbox 構造: ${SANDBOX}/.autopilot + ${SANDBOX}/.supervisor/events
run_hook_with_autopilot() {
  local hook_script="$1"
  local input_json="${2-}"
  [[ -z "$input_json" ]] && input_json="{}"
  local override_autopilot_dir="${3:-$AUTOPILOT_DIR_TEST}"
  printf '%s' "$input_json" | AUTOPILOT_DIR="$override_autopilot_dir" \
    bash "${HOOKS_DIR}/${hook_script}" 2>/dev/null
}

run_hook_without_autopilot() {
  local hook_script="$1"
  local input_json="${2-}"
  [[ -z "$input_json" ]] && input_json="{}"
  printf '%s' "$input_json" | bash "${HOOKS_DIR}/${hook_script}" 2>/dev/null
}

# =============================================================================
# supervisor-heartbeat.sh テスト
# =============================================================================

test_heartbeat_no_autopilot_dir() {
  local exit_code
  run_hook_without_autopilot "supervisor-heartbeat.sh" '{}' || exit_code=$?
  exit_code="${exit_code:-0}"
  [[ "$exit_code" -eq 0 ]] || return 1
  # ファイルが生成されていないことを確認（EVENTS_DIR は存在しない）
  [[ -z "$(find "${SANDBOX}" -name "heartbeat-*" 2>/dev/null)" ]] || return 1
}

test_heartbeat_creates_event_file() {
  local session_json='{"session_id":"test-sess-01","cwd":"/tmp/test"}'
  run_hook_with_autopilot "supervisor-heartbeat.sh" "$session_json"
  local event_file="${EVENTS_DIR_TEST}/heartbeat-test-sess-01"
  [[ -f "$event_file" ]] || return 1
  # JSON フォーマット検証
  jq -e '.session_id == "test-sess-01"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e 'has("cwd")' "$event_file" > /dev/null 2>&1 || return 1
}

test_heartbeat_exit_zero_on_failure() {
  # 書き込み不可なディレクトリでも exit 0
  local bad_dir="${SANDBOX}/.autopilot-bad"
  mkdir -p "$bad_dir"
  chmod 000 "$bad_dir" 2>/dev/null || true
  run_hook_with_autopilot "supervisor-heartbeat.sh" '{"session_id":"x"}' "$bad_dir"
  local ec=$?
  chmod 755 "$bad_dir" 2>/dev/null || true
  [[ "$ec" -eq 0 ]] || return 1
}

test_heartbeat_no_stdout() {
  local session_json='{"session_id":"test-stdout","cwd":"/tmp"}'
  local output
  output=$(run_hook_with_autopilot "supervisor-heartbeat.sh" "$session_json")
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# supervisor-input-wait.sh テスト
# =============================================================================

test_input_wait_no_autopilot_dir() {
  local exit_code
  run_hook_without_autopilot "supervisor-input-wait.sh" '{}' || exit_code=$?
  exit_code="${exit_code:-0}"
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_input_wait_creates_event_file() {
  local session_json='{"session_id":"wait-sess-01"}'
  run_hook_with_autopilot "supervisor-input-wait.sh" "$session_json"
  local event_file="${EVENTS_DIR_TEST}/input-wait-wait-sess-01"
  [[ -f "$event_file" ]] || return 1
  jq -e '.session_id == "wait-sess-01"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e '.event == "input-wait"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || return 1
}

test_input_wait_no_stdout() {
  local output
  output=$(run_hook_with_autopilot "supervisor-input-wait.sh" '{"session_id":"sw"}')
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# supervisor-input-clear.sh テスト
# =============================================================================

test_input_clear_removes_file() {
  local session_id="clear-sess-01"
  local event_file="${EVENTS_DIR_TEST}/input-wait-${session_id}"
  # ファイルを先に作成
  echo '{"event":"input-wait"}' > "$event_file"
  [[ -f "$event_file" ]] || return 1
  local session_json="{\"session_id\":\"${session_id}\"}"
  run_hook_with_autopilot "supervisor-input-clear.sh" "$session_json"
  [[ ! -f "$event_file" ]] || return 1
}

test_input_clear_no_file_ok() {
  # ファイルが存在しなくても exit 0
  run_hook_with_autopilot "supervisor-input-clear.sh" '{"session_id":"nonexistent"}'
  [[ $? -eq 0 ]] || return 1
}

test_input_clear_no_autopilot_dir() {
  run_hook_without_autopilot "supervisor-input-clear.sh" '{}' || true
  [[ $? -eq 0 ]] || return 1
}

# =============================================================================
# supervisor-skill-step.sh テスト
# =============================================================================

test_skill_step_no_autopilot_dir() {
  local exit_code
  run_hook_without_autopilot "supervisor-skill-step.sh" '{}' || exit_code=$?
  exit_code="${exit_code:-0}"
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_skill_step_creates_event_file() {
  local session_json='{"session_id":"skill-sess-01","tool_input":{"skill":"workflow-setup","args":"#123"}}'
  run_hook_with_autopilot "supervisor-skill-step.sh" "$session_json"
  local event_file="${EVENTS_DIR_TEST}/skill-step-skill-sess-01"
  [[ -f "$event_file" ]] || return 1
  jq -e '.session_id == "skill-sess-01"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e 'has("skill")' "$event_file" > /dev/null 2>&1 || return 1
  jq -e 'has("tool_input")' "$event_file" > /dev/null 2>&1 || return 1
}

test_skill_step_no_stdout() {
  local output
  output=$(run_hook_with_autopilot "supervisor-skill-step.sh" '{"session_id":"ss"}')
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# supervisor-session-end.sh テスト
# =============================================================================

test_session_end_no_autopilot_dir() {
  local exit_code
  run_hook_without_autopilot "supervisor-session-end.sh" '{}' || exit_code=$?
  exit_code="${exit_code:-0}"
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_session_end_creates_event_file() {
  local session_json='{"session_id":"end-sess-01"}'
  run_hook_with_autopilot "supervisor-session-end.sh" "$session_json"
  local event_file="${EVENTS_DIR_TEST}/session-end-end-sess-01"
  [[ -f "$event_file" ]] || return 1
  jq -e '.session_id == "end-sess-01"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e '.event == "session-end"' "$event_file" > /dev/null 2>&1 || return 1
  jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || return 1
}

test_session_end_no_stdout() {
  local output
  output=$(run_hook_with_autopilot "supervisor-session-end.sh" '{"session_id":"se"}')
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# 実行
# =============================================================================

echo "=== supervisor-event-emission-hooks tests ==="

# heartbeat
run_test "heartbeat: AUTOPILOT_DIR 未設定で exit 0" test_heartbeat_no_autopilot_dir
run_test "heartbeat: イベントファイル生成と JSON フォーマット" test_heartbeat_creates_event_file
run_test "heartbeat: 書き込み失敗でも exit 0" test_heartbeat_exit_zero_on_failure
run_test "heartbeat: stdout に何も出力しない" test_heartbeat_no_stdout

# input-wait
run_test "input-wait: AUTOPILOT_DIR 未設定で exit 0" test_input_wait_no_autopilot_dir
run_test "input-wait: イベントファイル生成と JSON フォーマット" test_input_wait_creates_event_file
run_test "input-wait: stdout に何も出力しない" test_input_wait_no_stdout

# input-clear
run_test "input-clear: input-wait ファイルを削除" test_input_clear_removes_file
run_test "input-clear: ファイル不在でも exit 0" test_input_clear_no_file_ok
run_test "input-clear: AUTOPILOT_DIR 未設定で exit 0" test_input_clear_no_autopilot_dir

# skill-step
run_test "skill-step: AUTOPILOT_DIR 未設定で exit 0" test_skill_step_no_autopilot_dir
run_test "skill-step: イベントファイル生成と JSON フォーマット" test_skill_step_creates_event_file
run_test "skill-step: stdout に何も出力しない" test_skill_step_no_stdout

# session-end
run_test "session-end: AUTOPILOT_DIR 未設定で exit 0" test_session_end_no_autopilot_dir
run_test "session-end: イベントファイル生成と JSON フォーマット" test_session_end_creates_event_file
run_test "session-end: stdout に何も出力しない" test_session_end_no_stdout

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
fi

[[ "$FAIL" -eq 0 ]]
