#!/usr/bin/env bash
# =============================================================================
# Functional Tests: supervisor-event-emission-hooks
# Tests the behavior of scripts/hooks/supervisor-*.sh
# Coverage: AUTOPILOT_DIR 設定あり/なし、git repo 内/外、JSON フォーマット検証、exit 0 保証
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

# git-common-dir ベースのイベントディレクトリ（fix後の新しい書き込み先）
GIT_COMMON_DIR=""
GIT_EVENTS_DIR=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  AUTOPILOT_DIR_TEST="${SANDBOX}/.autopilot"
  SUPERVISOR_DIR_TEST="${SANDBOX}/.supervisor"
  EVENTS_DIR_TEST="${SUPERVISOR_DIR_TEST}/events"
  mkdir -p "$AUTOPILOT_DIR_TEST"
  mkdir -p "$EVENTS_DIR_TEST"
  # git-common-dir からイベントディレクトリを解決
  GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
  if [[ -n "$GIT_COMMON_DIR" ]]; then
    GIT_EVENTS_DIR="${GIT_COMMON_DIR}/../main/.supervisor/events"
  else
    GIT_EVENTS_DIR=""
  fi
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
  AUTOPILOT_DIR_TEST=""
  EVENTS_DIR_TEST=""
  SUPERVISOR_DIR_TEST=""
  GIT_COMMON_DIR=""
  GIT_EVENTS_DIR=""
}

# テスト生成ファイルを git-events-dir からクリーンアップ
cleanup_git_event_file() {
  local filename="$1"
  if [[ -n "$GIT_EVENTS_DIR" ]]; then
    rm -f "${GIT_EVENTS_DIR}/${filename}" 2>/dev/null || true
    rm -f "${GIT_EVENTS_DIR}/${filename}.tmp."* 2>/dev/null || true
  fi
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

# AUTOPILOT_DIR なしで hook を実行（非 git 環境エミュレート用 or レガシーテスト）
# AUTOPILOT_DIR を明示的に unset して実行（親セッションの環境変数を引き継がない）
run_hook_without_autopilot() {
  local hook_script="$1"
  local input_json="${2-}"
  [[ -z "$input_json" ]] && input_json="{}"
  printf '%s' "$input_json" | env -u AUTOPILOT_DIR bash "${HOOKS_DIR}/${hook_script}" 2>/dev/null
}

# AUTOPILOT_DIR 未設定で、実際の git repo 内（現在の worktree）から hook を実行
# fix 後の新動作: git rev-parse --git-common-dir を使って EVENTS_DIR を解決
# 書き込み先: main/.supervisor/events/（GIT_EVENTS_DIR）
# AUTOPILOT_DIR を明示的に unset して実行（親セッションの環境変数を引き継がない）
run_hook_in_git_repo_no_autopilot() {
  local hook_script="$1"
  local input_json="${2:-{}}"
  printf '%s' "$input_json" | env -u AUTOPILOT_DIR bash "${HOOKS_DIR}/${hook_script}" 2>/dev/null
}

# =============================================================================
# supervisor-heartbeat.sh テスト
# =============================================================================

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → イベントファイルが GIT_EVENTS_DIR に生成される（fix後の新動作）
test_heartbeat_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-heartbeat"}'
  run_hook_in_git_repo_no_autopilot "supervisor-heartbeat.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/heartbeat-test-no-ap-heartbeat"
  local result=0
  # イベントファイルが生成されていることを確認
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-heartbeat"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "heartbeat-test-no-ap-heartbeat"
  return $result
}

# git 外セッション（非 git 環境）での静的終了: AUTOPILOT_DIR 未設定 + git repo 外 → exit 0
test_heartbeat_no_autopilot_dir() {
  local exit_code
  # git rev-parse が失敗する環境を再現するため /tmp 配下で実行
  ( cd /tmp && printf '{}' | bash "${HOOKS_DIR}/supervisor-heartbeat.sh" 2>/dev/null )
  exit_code=$?
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_heartbeat_creates_event_file() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-sess-01","cwd":"/tmp/test"}'
  run_hook_with_autopilot "supervisor-heartbeat.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/heartbeat-test-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    # JSON フォーマット検証
    jq -e '.session_id == "test-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("cwd")' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "heartbeat-test-sess-01"
  return $result
}

test_heartbeat_exit_zero_on_failure() {
  # hook は常に exit 0 を保証する（書き込み失敗時も含む）
  # git 外環境（/tmp）でも exit 0 になることを確認（git rev-parse 失敗 → 早期 exit 0）
  local ec
  ( cd /tmp && printf '{"session_id":"x"}' | bash "${HOOKS_DIR}/supervisor-heartbeat.sh" 2>/dev/null )
  ec=$?
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

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → input-wait イベントファイルが生成される（fix後の新動作）
test_input_wait_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-input-wait"}'
  run_hook_in_git_repo_no_autopilot "supervisor-input-wait.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/input-wait-test-no-ap-input-wait"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-input-wait"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "input-wait"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "input-wait-test-no-ap-input-wait"
  return $result
}

# git 外セッションでの静的終了: AUTOPILOT_DIR 未設定 + git repo 外 → exit 0
test_input_wait_no_autopilot_dir() {
  local exit_code
  ( cd /tmp && printf '{}' | bash "${HOOKS_DIR}/supervisor-input-wait.sh" 2>/dev/null )
  exit_code=$?
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_input_wait_creates_event_file() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"wait-sess-01"}'
  run_hook_with_autopilot "supervisor-input-wait.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/input-wait-wait-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "wait-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "input-wait"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "input-wait-wait-sess-01"
  return $result
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
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_id="clear-sess-01"
  # hook は GIT_EVENTS_DIR に書くので、ファイルも GIT_EVENTS_DIR に作成する
  mkdir -p "$GIT_EVENTS_DIR"
  local event_file="${GIT_EVENTS_DIR}/input-wait-${session_id}"
  echo '{"event":"input-wait"}' > "$event_file"
  [[ -f "$event_file" ]] || return 1
  local session_json="{\"session_id\":\"${session_id}\"}"
  run_hook_with_autopilot "supervisor-input-clear.sh" "$session_json"
  local result=0
  [[ ! -f "$event_file" ]] || result=1
  cleanup_git_event_file "input-wait-${session_id}"
  return $result
}

test_input_clear_no_file_ok() {
  # ファイルが存在しなくても exit 0
  run_hook_with_autopilot "supervisor-input-clear.sh" '{"session_id":"nonexistent"}'
  [[ $? -eq 0 ]] || return 1
}

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → input-wait ファイルを削除する（fix後の新動作）
test_input_clear_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_id="test-no-ap-input-clear"
  # 先に input-wait ファイルを作成
  mkdir -p "$GIT_EVENTS_DIR"
  printf '{"event":"input-wait","session_id":"%s"}\n' "$session_id" > "${GIT_EVENTS_DIR}/input-wait-${session_id}"
  [[ -f "${GIT_EVENTS_DIR}/input-wait-${session_id}" ]] || return 1
  local session_json="{\"session_id\":\"${session_id}\"}"
  run_hook_in_git_repo_no_autopilot "supervisor-input-clear.sh" "$session_json"
  local result=0
  # ファイルが削除されていることを確認
  [[ ! -f "${GIT_EVENTS_DIR}/input-wait-${session_id}" ]] || result=1
  # 念のためクリーンアップ
  cleanup_git_event_file "input-wait-${session_id}"
  return $result
}

# git 外セッションでの静的終了: AUTOPILOT_DIR 未設定 + git repo 外 → exit 0
test_input_clear_no_autopilot_dir() {
  local exit_code
  ( cd /tmp && printf '{}' | bash "${HOOKS_DIR}/supervisor-input-clear.sh" 2>/dev/null )
  exit_code=$?
  [[ "$exit_code" -eq 0 ]] || return 1
}

# =============================================================================
# supervisor-skill-step.sh テスト
# =============================================================================

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → skill-step イベントファイルが生成される（fix後の新動作）
test_skill_step_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-skill-step","tool_input":{"skill":"workflow-setup","args":"#725"}}'
  run_hook_in_git_repo_no_autopilot "supervisor-skill-step.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/skill-step-test-no-ap-skill-step"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-skill-step"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("skill")' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "skill-step-test-no-ap-skill-step"
  return $result
}

# git 外セッションでの静的終了: AUTOPILOT_DIR 未設定 + git repo 外 → exit 0
test_skill_step_no_autopilot_dir() {
  local exit_code
  ( cd /tmp && printf '{}' | bash "${HOOKS_DIR}/supervisor-skill-step.sh" 2>/dev/null )
  exit_code=$?
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_skill_step_creates_event_file() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"skill-sess-01","tool_input":{"skill":"workflow-setup","args":"#123"}}'
  run_hook_with_autopilot "supervisor-skill-step.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/skill-step-skill-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "skill-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("skill")' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("tool_input")' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "skill-step-skill-sess-01"
  return $result
}

test_skill_step_no_stdout() {
  local output
  output=$(run_hook_with_autopilot "supervisor-skill-step.sh" '{"session_id":"ss"}')
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# supervisor-session-end.sh テスト
# =============================================================================

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → session-end イベントファイルが生成される（fix後の新動作）
test_session_end_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-session-end"}'
  run_hook_in_git_repo_no_autopilot "supervisor-session-end.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/session-end-test-no-ap-session-end"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-session-end"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "session-end"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "session-end-test-no-ap-session-end"
  return $result
}

# git 外セッションでの静的終了: AUTOPILOT_DIR 未設定 + git repo 外 → exit 0
test_session_end_no_autopilot_dir() {
  local exit_code
  ( cd /tmp && printf '{}' | bash "${HOOKS_DIR}/supervisor-session-end.sh" 2>/dev/null )
  exit_code=$?
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_session_end_creates_event_file() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"end-sess-01"}'
  run_hook_with_autopilot "supervisor-session-end.sh" "$session_json"
  local event_file="${GIT_EVENTS_DIR}/session-end-end-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "end-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "session-end"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  cleanup_git_event_file "session-end-end-sess-01"
  return $result
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
run_test "heartbeat: AUTOPILOT_DIR 未設定 + git 内でイベントファイル生成（fix後）" test_heartbeat_no_autopilot_in_git_repo
run_test "heartbeat: git 外セッションで exit 0（静的終了）" test_heartbeat_no_autopilot_dir
run_test "heartbeat: イベントファイル生成と JSON フォーマット（AUTOPILOT_DIR あり）" test_heartbeat_creates_event_file
run_test "heartbeat: 書き込み失敗でも exit 0" test_heartbeat_exit_zero_on_failure
run_test "heartbeat: stdout に何も出力しない" test_heartbeat_no_stdout

# input-wait
run_test "input-wait: AUTOPILOT_DIR 未設定 + git 内でイベントファイル生成（fix後）" test_input_wait_no_autopilot_in_git_repo
run_test "input-wait: git 外セッションで exit 0（静的終了）" test_input_wait_no_autopilot_dir
run_test "input-wait: イベントファイル生成と JSON フォーマット（AUTOPILOT_DIR あり）" test_input_wait_creates_event_file
run_test "input-wait: stdout に何も出力しない" test_input_wait_no_stdout

# input-clear
run_test "input-clear: input-wait ファイルを削除（AUTOPILOT_DIR あり）" test_input_clear_removes_file
run_test "input-clear: ファイル不在でも exit 0" test_input_clear_no_file_ok
run_test "input-clear: AUTOPILOT_DIR 未設定 + git 内で input-wait ファイルを削除（fix後）" test_input_clear_no_autopilot_in_git_repo
run_test "input-clear: git 外セッションで exit 0（静的終了）" test_input_clear_no_autopilot_dir

# skill-step
run_test "skill-step: AUTOPILOT_DIR 未設定 + git 内でイベントファイル生成（fix後）" test_skill_step_no_autopilot_in_git_repo
run_test "skill-step: git 外セッションで exit 0（静的終了）" test_skill_step_no_autopilot_dir
run_test "skill-step: イベントファイル生成と JSON フォーマット（AUTOPILOT_DIR あり）" test_skill_step_creates_event_file
run_test "skill-step: stdout に何も出力しない" test_skill_step_no_stdout

# session-end
run_test "session-end: AUTOPILOT_DIR 未設定 + git 内でイベントファイル生成（fix後）" test_session_end_no_autopilot_in_git_repo
run_test "session-end: git 外セッションで exit 0（静的終了）" test_session_end_no_autopilot_dir
run_test "session-end: イベントファイル生成と JSON フォーマット（AUTOPILOT_DIR あり）" test_session_end_creates_event_file
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
