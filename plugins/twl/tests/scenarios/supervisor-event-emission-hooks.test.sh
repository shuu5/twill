#!/usr/bin/env bash
# =============================================================================
# Functional Tests: supervisor-event-emission-hooks
# Tests the behavior of scripts/hooks/supervisor-*.sh
# Coverage: sandbox 書き込み分離、git repo 内/外、JSON フォーマット検証、exit 0 保証
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
HOOK_STDERR=""

# git-common-dir ベースの変数（skip 判定と AC-3 用）
GIT_COMMON_DIR=""
GIT_EVENTS_DIR=""

# AC-6: 異常終了でも teardown_sandbox が走るよう trap を設定
trap teardown_sandbox INT TERM EXIT

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  AUTOPILOT_DIR_TEST="${SANDBOX}/.autopilot"
  SUPERVISOR_DIR_TEST="${SANDBOX}/.supervisor"
  EVENTS_DIR_TEST="${SUPERVISOR_DIR_TEST}/events"
  mkdir -p "$AUTOPILOT_DIR_TEST"
  mkdir -p "$EVENTS_DIR_TEST"
  # hook の書き込み先を sandbox に向ける（AC-2: production 汚染防止）
  export TWL_SUPERVISOR_EVENTS_DIR="${SANDBOX}/.supervisor/events"
  # git-common-dir からイベントディレクトリを解決（skip 判定と AC-3 用）
  GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
  if [[ -n "$GIT_COMMON_DIR" ]]; then
    GIT_EVENTS_DIR="${GIT_COMMON_DIR}/../main/.supervisor/events"
  else
    GIT_EVENTS_DIR=""
  fi
  # AC-3: 副作用検証用マーカー
  touch "${SANDBOX}/test_start_marker"
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
  unset TWL_SUPERVISOR_EVENTS_DIR 2>/dev/null || true
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  setup_sandbox
  result=0
  $func || result=$?
  # AC-3: teardown_sandbox 直前に production events への書き込みなしを検証
  if [[ -n "$GIT_EVENTS_DIR" && -d "$GIT_EVENTS_DIR" && -f "${SANDBOX}/test_start_marker" ]]; then
    local leaked
    leaked=$(find "$GIT_EVENTS_DIR" -newer "${SANDBOX}/test_start_marker" 2>/dev/null | wc -l)
    if [[ "$leaked" -gt 0 ]]; then
      echo "  FAIL (AC-3): production events dir contaminated (${leaked} new files)" >&2
      result=1
    fi
  fi
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

# supervisor-* hook は AUTOPILOT_DIR を参照しない（git rev-parse --git-common-dir で events_dir を解決）
# TWL_SUPERVISOR_EVENTS_DIR は setup_sandbox で export 済みのため自動伝搬
run_hook() {
  local hook_script="$1"
  local input_json="${2:-{}}"
  printf '%s' "$input_json" | bash "${HOOKS_DIR}/${hook_script}" 2>/dev/null
}

# stderr を変数 HOOK_STDERR にキャプチャして hook を実行（AC-5/6/7 用）
# TWL_SUPERVISOR_EVENTS_DIR は setup_sandbox で export 済みのため自動伝搬
run_hook_capture_stderr() {
  local hook_script="$1"
  local input_json="${2:-{}}"
  local _tmpfile
  _tmpfile=$(mktemp)
  printf '%s' "$input_json" | bash "${HOOKS_DIR}/${hook_script}" >/dev/null 2>"$_tmpfile"
  local _rc=${PIPESTATUS[1]}
  HOOK_STDERR=$(cat "$_tmpfile")
  rm -f "$_tmpfile"
  return $_rc
}

# non-bare git リポジトリ（.git/ のみ、main/ 不在）から hook を実行
# AC-1/AC-2a/AC-2b 用: git init サンドボックスで bare repo 構造ガードを検証
run_hook_in_non_bare() {
  local hook_script="$1"
  local input_json="${2:-{}}"
  local non_bare_dir
  non_bare_dir=$(mktemp -d)
  (
    cd "$non_bare_dir" && git init -q 2>/dev/null &&
    printf '%s' "$input_json" | env -u AUTOPILOT_DIR bash "${HOOKS_DIR}/${hook_script}" 2>/dev/null
  )
  local rc=$?
  rm -rf "$non_bare_dir" 2>/dev/null
  return $rc
}

# =============================================================================
# supervisor-heartbeat.sh テスト
# =============================================================================

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → イベントファイルが sandbox に生成される
test_heartbeat_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-heartbeat"}'
  run_hook "supervisor-heartbeat.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/heartbeat-test-no-ap-heartbeat"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-heartbeat"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  return $result
}

# git 外セッション（非 git 環境）での静的終了: AUTOPILOT_DIR 未設定 + git repo 外 → exit 0
test_heartbeat_no_autopilot_dir() {
  local exit_code
  ( cd /tmp && printf '{}' | bash "${HOOKS_DIR}/supervisor-heartbeat.sh" 2>/dev/null )
  exit_code=$?
  [[ "$exit_code" -eq 0 ]] || return 1
}

test_heartbeat_creates_event_file() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-sess-01","cwd":"/tmp/test"}'
  run_hook "supervisor-heartbeat.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/heartbeat-test-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    # JSON フォーマット検証
    jq -e '.session_id == "test-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("cwd")' "$event_file" > /dev/null 2>&1 || result=1
  fi
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
  output=$(run_hook "supervisor-heartbeat.sh" "$session_json")
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# supervisor-input-wait.sh テスト
# =============================================================================

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → input-wait イベントファイルが sandbox に生成される
test_input_wait_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-input-wait"}'
  run_hook "supervisor-input-wait.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-test-no-ap-input-wait"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-input-wait"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "input-wait"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
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
  run_hook "supervisor-input-wait.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-wait-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "wait-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "input-wait"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  return $result
}

test_input_wait_no_stdout() {
  local output
  output=$(run_hook "supervisor-input-wait.sh" '{"session_id":"sw"}')
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# supervisor-input-clear.sh テスト
# =============================================================================

test_input_clear_removes_file() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_id="clear-sess-01"
  # hook は TWL_SUPERVISOR_EVENTS_DIR に書くので、ファイルも sandbox に作成する
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-${session_id}"
  echo '{"event":"input-wait"}' > "$event_file"
  [[ -f "$event_file" ]] || return 1
  local session_json="{\"session_id\":\"${session_id}\"}"
  run_hook "supervisor-input-clear.sh" "$session_json"
  local result=0
  [[ ! -f "$event_file" ]] || result=1
  return $result
}

test_input_clear_no_file_ok() {
  # ファイルが存在しなくても exit 0
  run_hook "supervisor-input-clear.sh" '{"session_id":"nonexistent"}'
  [[ $? -eq 0 ]] || return 1
}

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → sandbox の input-wait ファイルを削除する
test_input_clear_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_id="test-no-ap-input-clear"
  # 先に input-wait ファイルを sandbox に作成
  printf '{"event":"input-wait","session_id":"%s"}\n' "$session_id" > "${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-${session_id}"
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-${session_id}" ]] || return 1
  local session_json="{\"session_id\":\"${session_id}\"}"
  run_hook "supervisor-input-clear.sh" "$session_json"
  local result=0
  # ファイルが削除されていることを確認
  [[ ! -f "${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-${session_id}" ]] || result=1
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

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → skill-step イベントファイルが sandbox に生成される
test_skill_step_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-skill-step","tool_input":{"skill":"workflow-setup","args":"#725"}}'
  run_hook "supervisor-skill-step.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/skill-step-test-no-ap-skill-step"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-skill-step"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("skill")' "$event_file" > /dev/null 2>&1 || result=1
  fi
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
  run_hook "supervisor-skill-step.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/skill-step-skill-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "skill-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("skill")' "$event_file" > /dev/null 2>&1 || result=1
    jq -e 'has("tool_input")' "$event_file" > /dev/null 2>&1 || result=1
  fi
  return $result
}

test_skill_step_no_stdout() {
  local output
  output=$(run_hook "supervisor-skill-step.sh" '{"session_id":"ss"}')
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# supervisor-session-end.sh テスト
# =============================================================================

# AUTOPILOT_DIR 未設定かつ git リポジトリ内 → session-end イベントファイルが sandbox に生成される
test_session_end_no_autopilot_in_git_repo() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"test-no-ap-session-end"}'
  run_hook "supervisor-session-end.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/session-end-test-no-ap-session-end"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "test-no-ap-session-end"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "session-end"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
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
  run_hook "supervisor-session-end.sh" "$session_json"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/session-end-end-sess-01"
  local result=0
  [[ -f "$event_file" ]] || result=1
  if [[ $result -eq 0 ]]; then
    jq -e '.session_id == "end-sess-01"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.event == "session-end"' "$event_file" > /dev/null 2>&1 || result=1
    jq -e '.timestamp | type == "number"' "$event_file" > /dev/null 2>&1 || result=1
  fi
  return $result
}

test_session_end_no_stdout() {
  local output
  output=$(run_hook "supervisor-session-end.sh" '{"session_id":"se"}')
  [[ -z "$output" ]] || return 1
}

# =============================================================================
# AC-5/AC-6/AC-7: SESSION_ID path-traversal サニタイズテスト
# =============================================================================

# AC-5: heartbeat - SESSION_ID=../evil でファイル名が sanitize され EVENTS_DIR 外への書き込みなし
test_heartbeat_path_traversal() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"../evil"}'
  run_hook_capture_stderr "supervisor-heartbeat.sh" "$session_json"
  local result=0
  # (a) EVENTS_DIR の外にファイルが生成されない（../evil → ${EVENTS_DIR}/../evil）
  [[ ! -f "${TWL_SUPERVISOR_EVENTS_DIR}/../evil" ]] || result=1
  # (b) サニタイズ後の名前でファイルが生成される（../が除去されて evil のみ残る）
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/heartbeat-evil" ]] || result=1
  # (c) stderr 警告が出力される
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' || result=1
  return $result
}

# AC-5: input-wait - SESSION_ID=../evil でファイル名が sanitize され EVENTS_DIR 外への書き込みなし
test_input_wait_path_traversal() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"../evil"}'
  run_hook_capture_stderr "supervisor-input-wait.sh" "$session_json"
  local result=0
  [[ ! -f "${TWL_SUPERVISOR_EVENTS_DIR}/../evil" ]] || result=1
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-evil" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' || result=1
  return $result
}

# AC-5: skill-step - SESSION_ID=../evil でファイル名が sanitize され EVENTS_DIR 外への書き込みなし
test_skill_step_path_traversal() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"../evil","tool_input":{"skill":"test"}}'
  run_hook_capture_stderr "supervisor-skill-step.sh" "$session_json"
  local result=0
  [[ ! -f "${TWL_SUPERVISOR_EVENTS_DIR}/../evil" ]] || result=1
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/skill-step-evil" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' || result=1
  return $result
}

# AC-5: session-end - SESSION_ID=../evil でファイル名が sanitize され EVENTS_DIR 外への書き込みなし
test_session_end_path_traversal() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local session_json='{"session_id":"../evil"}'
  run_hook_capture_stderr "supervisor-session-end.sh" "$session_json"
  local result=0
  [[ ! -f "${TWL_SUPERVISOR_EVENTS_DIR}/../evil" ]] || result=1
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/session-end-evil" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' || result=1
  return $result
}

# AC-6: input-clear - SESSION_ID=../secret で canary ファイルが削除されない
test_input_clear_path_traversal() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  # canary を EVENTS_DIR の親（traverse 先）に配置
  local canary="${TWL_SUPERVISOR_EVENTS_DIR}/../secret"
  touch "$canary" 2>/dev/null || { echo "  SKIP: cannot create canary" >&2; return 0; }
  local session_json='{"session_id":"../secret"}'
  run_hook_capture_stderr "supervisor-input-clear.sh" "$session_json"
  local result=0
  # canary が残存している（rm が EVENTS_DIR 外に到達しなかった）
  [[ -f "$canary" ]] || result=1
  # stderr 警告が出力される
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' || result=1
  rm -f "$canary" 2>/dev/null
  return $result
}

# AC-7: heartbeat - UUID v4 SESSION_ID はサニタイズで変化せず、stderr 警告なし
test_heartbeat_uuid_no_warn() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local uuid="3f2504e0-4f89-41d3-9a0c-0305e82c3301"
  local session_json="{\"session_id\":\"${uuid}\"}"
  run_hook_capture_stderr "supervisor-heartbeat.sh" "$session_json"
  local result=0
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/heartbeat-${uuid}" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' && result=1
  return $result
}

# AC-7: input-wait - UUID v4 はサニタイズで変化せず、stderr 警告なし
test_input_wait_uuid_no_warn() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local uuid="3f2504e0-4f89-41d3-9a0c-0305e82c3301"
  local session_json="{\"session_id\":\"${uuid}\"}"
  run_hook_capture_stderr "supervisor-input-wait.sh" "$session_json"
  local result=0
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-${uuid}" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' && result=1
  return $result
}

# AC-7: skill-step - UUID v4 はサニタイズで変化せず、stderr 警告なし
test_skill_step_uuid_no_warn() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local uuid="3f2504e0-4f89-41d3-9a0c-0305e82c3301"
  local session_json="{\"session_id\":\"${uuid}\",\"tool_input\":{\"skill\":\"test\"}}"
  run_hook_capture_stderr "supervisor-skill-step.sh" "$session_json"
  local result=0
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/skill-step-${uuid}" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' && result=1
  return $result
}

# AC-7: session-end - UUID v4 はサニタイズで変化せず、stderr 警告なし
test_session_end_uuid_no_warn() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local uuid="3f2504e0-4f89-41d3-9a0c-0305e82c3301"
  local session_json="{\"session_id\":\"${uuid}\"}"
  run_hook_capture_stderr "supervisor-session-end.sh" "$session_json"
  local result=0
  [[ -f "${TWL_SUPERVISOR_EVENTS_DIR}/session-end-${uuid}" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' && result=1
  return $result
}

# AC-7: input-clear - UUID v4 では rm が正しいファイルを削除し、stderr 警告なし
test_input_clear_uuid_no_warn() {
  [[ -n "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: not in git repo" >&2; return 0; }
  local uuid="3f2504e0-4f89-41d3-9a0c-0305e82c3301"
  local event_file="${TWL_SUPERVISOR_EVENTS_DIR}/input-wait-${uuid}"
  echo '{"event":"input-wait"}' > "$event_file"
  local session_json="{\"session_id\":\"${uuid}\"}"
  run_hook_capture_stderr "supervisor-input-clear.sh" "$session_json"
  local result=0
  [[ ! -f "$event_file" ]] || result=1
  printf '%s' "$HOOK_STDERR" | grep -q '\[supervisor-hook\]\[warn\] SESSION_ID sanitized' && result=1
  return $result
}

# =============================================================================
# non-bare 検出テスト（AC-1/AC-2a/AC-2b: bare repo 構造ガード）
# サンドボックス: git init のみ（.git/ 構造）、main/ ディレクトリなし
# =============================================================================

test_heartbeat_non_bare_exit_zero() {
  run_hook_in_non_bare "supervisor-heartbeat.sh" '{"session_id":"nb-heartbeat"}'
  [[ $? -eq 0 ]] || return 1
}

test_input_wait_non_bare_exit_zero() {
  run_hook_in_non_bare "supervisor-input-wait.sh" '{"session_id":"nb-input-wait"}'
  [[ $? -eq 0 ]] || return 1
}

test_input_clear_non_bare_exit_zero() {
  run_hook_in_non_bare "supervisor-input-clear.sh" '{"session_id":"nb-input-clear"}'
  [[ $? -eq 0 ]] || return 1
}

test_skill_step_non_bare_exit_zero() {
  run_hook_in_non_bare "supervisor-skill-step.sh" '{"session_id":"nb-skill-step","tool_input":{"skill":"test"}}'
  [[ $? -eq 0 ]] || return 1
}

test_session_end_non_bare_exit_zero() {
  run_hook_in_non_bare "supervisor-session-end.sh" '{"session_id":"nb-session-end"}'
  [[ $? -eq 0 ]] || return 1
}

# AC-2b: non-bare 環境で .supervisor/events/ への書き込みが発生しないことを明示検証
test_heartbeat_non_bare_no_events_written() {
  local non_bare_dir
  non_bare_dir=$(mktemp -d)
  local result=0
  (
    cd "$non_bare_dir" && git init -q 2>/dev/null &&
    printf '{"session_id":"nb-ac2b"}' | env -u AUTOPILOT_DIR bash "${HOOKS_DIR}/supervisor-heartbeat.sh" 2>/dev/null
  )
  # .supervisor/ ディレクトリが作成されていないことを確認
  [[ ! -d "${non_bare_dir}/.supervisor" ]] || result=1
  # bare ガードにより main/ 自体が作成されないことを確認（main/以下への書き込みなし）
  [[ ! -d "${non_bare_dir}/main" ]] || result=1
  rm -rf "$non_bare_dir" 2>/dev/null
  return $result
}

# =============================================================================
# AC-6: 異常終了耐性テスト（SIGTERM 後に production events 汚染なし）
# =============================================================================

test_sigint_no_residual_files() {
  [[ -n "$GIT_EVENTS_DIR" && -d "$GIT_EVENTS_DIR" ]] || { echo "  SKIP: no production events dir" >&2; return 0; }
  # 再帰実行を防ぐガード（_SIGINT_TEST_RUNNING が set されている場合は skip）
  [[ -z "${_SIGINT_TEST_RUNNING:-}" ]] || { echo "  SKIP: nested run" >&2; return 0; }
  local marker
  marker=$(mktemp)
  sleep 0.05  # marker timestamp を settle させる
  # このスクリプト自体を短い timeout で実行（SIGTERM により中断される）
  # _SIGINT_TEST_RUNNING=1 で再帰実行ガードを有効化
  _SIGINT_TEST_RUNNING=1 timeout 0.5 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1 || true
  local leaked
  leaked=$(find "$GIT_EVENTS_DIR" -newer "$marker" 2>/dev/null | wc -l)
  rm -f "$marker"
  [[ "$leaked" -eq 0 ]] || return 1
}

# =============================================================================
# 実行
# =============================================================================

echo "=== supervisor-event-emission-hooks tests ==="

# heartbeat
run_test "heartbeat: git_common_dir 解決でイベントファイル生成（sandbox）" test_heartbeat_no_autopilot_in_git_repo
run_test "heartbeat: git 外セッションで exit 0（静的終了）" test_heartbeat_no_autopilot_dir
run_test "heartbeat: イベントファイル生成と JSON フォーマット（sandbox）" test_heartbeat_creates_event_file
run_test "heartbeat: 書き込み失敗でも exit 0" test_heartbeat_exit_zero_on_failure
run_test "heartbeat: stdout に何も出力しない" test_heartbeat_no_stdout

# input-wait
run_test "input-wait: git_common_dir 解決でイベントファイル生成（sandbox）" test_input_wait_no_autopilot_in_git_repo
run_test "input-wait: git 外セッションで exit 0（静的終了）" test_input_wait_no_autopilot_dir
run_test "input-wait: イベントファイル生成と JSON フォーマット（sandbox）" test_input_wait_creates_event_file
run_test "input-wait: stdout に何も出力しない" test_input_wait_no_stdout

# input-clear
run_test "input-clear: input-wait ファイルを削除（sandbox）" test_input_clear_removes_file
run_test "input-clear: ファイル不在でも exit 0" test_input_clear_no_file_ok
run_test "input-clear: git_common_dir 解決で sandbox の input-wait ファイルを削除" test_input_clear_no_autopilot_in_git_repo
run_test "input-clear: git 外セッションで exit 0（静的終了）" test_input_clear_no_autopilot_dir

# skill-step
run_test "skill-step: git_common_dir 解決でイベントファイル生成（sandbox）" test_skill_step_no_autopilot_in_git_repo
run_test "skill-step: git 外セッションで exit 0（静的終了）" test_skill_step_no_autopilot_dir
run_test "skill-step: イベントファイル生成と JSON フォーマット（sandbox）" test_skill_step_creates_event_file
run_test "skill-step: stdout に何も出力しない" test_skill_step_no_stdout

# session-end
run_test "session-end: git_common_dir 解決でイベントファイル生成（sandbox）" test_session_end_no_autopilot_in_git_repo
run_test "session-end: git 外セッションで exit 0（静的終了）" test_session_end_no_autopilot_dir
run_test "session-end: イベントファイル生成と JSON フォーマット（sandbox）" test_session_end_creates_event_file
run_test "session-end: stdout に何も出力しない" test_session_end_no_stdout

# AC-5: path-traversal write hooks（../evil）
run_test "heartbeat: SESSION_ID=../evil でサニタイズ・EVENTS_DIR 外書き込みなし（AC-5）" test_heartbeat_path_traversal
run_test "input-wait: SESSION_ID=../evil でサニタイズ・EVENTS_DIR 外書き込みなし（AC-5）" test_input_wait_path_traversal
run_test "skill-step: SESSION_ID=../evil でサニタイズ・EVENTS_DIR 外書き込みなし（AC-5）" test_skill_step_path_traversal
run_test "session-end: SESSION_ID=../evil でサニタイズ・EVENTS_DIR 外書き込みなし（AC-5）" test_session_end_path_traversal

# AC-6: path-traversal rm hook（../secret canary 保護）
run_test "input-clear: SESSION_ID=../secret で canary ファイル保護・stderr 警告（AC-6）" test_input_clear_path_traversal

# AC-7: UUID v4 非破壊・stderr 警告なし
run_test "heartbeat: UUID v4 SESSION_ID でサニタイズなし・警告出力なし（AC-7）" test_heartbeat_uuid_no_warn
run_test "input-wait: UUID v4 SESSION_ID でサニタイズなし・警告出力なし（AC-7）" test_input_wait_uuid_no_warn
run_test "skill-step: UUID v4 SESSION_ID でサニタイズなし・警告出力なし（AC-7）" test_skill_step_uuid_no_warn
run_test "session-end: UUID v4 SESSION_ID でサニタイズなし・警告出力なし（AC-7）" test_session_end_uuid_no_warn
run_test "input-clear: UUID v4 SESSION_ID でサニタイズなし・警告出力なし（AC-7）" test_input_clear_uuid_no_warn

# non-bare 検出（AC-1/AC-2a: bare repo 構造ガード）
run_test "heartbeat: non-bare リポジトリで exit 0（no-op）" test_heartbeat_non_bare_exit_zero
run_test "input-wait: non-bare リポジトリで exit 0（no-op）" test_input_wait_non_bare_exit_zero
run_test "input-clear: non-bare リポジトリで exit 0（no-op）" test_input_clear_non_bare_exit_zero
run_test "skill-step: non-bare リポジトリで exit 0（no-op）" test_skill_step_non_bare_exit_zero
run_test "session-end: non-bare リポジトリで exit 0（no-op）" test_session_end_non_bare_exit_zero
run_test "heartbeat: non-bare で .supervisor/events/ への書き込みなし（AC-2b）" test_heartbeat_non_bare_no_events_written

# AC-6: 異常終了耐性
run_test "AC-6: SIGTERM 後に production events ディレクトリ汚染なし" test_sigint_no_residual_files

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
fi

[[ "$FAIL" -eq 0 ]]
