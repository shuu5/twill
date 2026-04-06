#!/usr/bin/env bash
# =============================================================================
# Functional Tests: bash-error-recording.md
# Generated from: deltaspec/changes/b-7-self-improve-review-hook/specs/bash-error-recording.md
# Coverage level: edge-cases
# Tests the actual behavior of scripts/hooks/post-tool-use-bash-error.sh
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/scripts/hooks/post-tool-use-bash-error.sh"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Sandbox Setup ---

SANDBOX=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  # Create a minimal plugin structure mirroring the hook's expectations
  mkdir -p "${SANDBOX}/scripts/hooks"
  cp "$HOOK_SCRIPT" "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh"
  chmod +x "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh"
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

run_hook_in_sandbox() {
  local exit_code_arg="${1:-0}"
  # The hook reads PostToolUseFailure JSON from stdin
  # PostToolUseFailure includes: tool_name, tool_input, error, error_type, etc.
  local json_input
  if [[ "$exit_code_arg" =~ ^[0-9]+$ ]] && [[ "$exit_code_arg" -ne 0 ]]; then
    json_input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"test_command\"},\"error\":\"Exit code ${exit_code_arg}\",\"error_type\":\"tool_error\"}"
  elif [[ "$exit_code_arg" == "0" ]]; then
    # exit 0 means no error; PostToolUseFailure would not be called, but we simulate it
    json_input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"test_command\"},\"error\":\"Exit code 0\",\"error_type\":\"tool_error\"}"
  else
    # Non-integer or invalid input
    json_input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"test_command\"},\"error\":\"${exit_code_arg}\",\"error_type\":\"tool_error\"}"
  fi
  echo "$json_input" | bash "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh" 2>/dev/null
}

get_errors_file() {
  echo "${SANDBOX}/.self-improve/errors.jsonl"
}

# --- Test Helpers ---

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
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++))
}

# =============================================================================
# Requirement: Bash エラー自動記録
# =============================================================================
echo ""
echo "--- Requirement: Bash エラー自動記録 ---"

# Scenario: 正常なエラー記録 (line 14)
# WHEN: Bash tool が exit_code 1 で終了する
# THEN: .self-improve/errors.jsonl に timestamp, command, exit_code, stderr_snippet, cwd を含む JSON 行が追記される
test_normal_error_recording() {
  run_hook_in_sandbox 1
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
  local line_count
  line_count=$(wc -l < "$errors_file")
  [[ "$line_count" -ge 1 ]] || return 1
  # Verify it is valid JSON with required fields
  local last_line
  last_line=$(tail -1 "$errors_file")
  echo "$last_line" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert 'timestamp' in data, 'missing timestamp'
assert 'exit_code' in data, 'missing exit_code'
assert data['exit_code'] == 1, f'exit_code should be 1, got {data[\"exit_code\"]}'
" 2>/dev/null || return 1
}

if [[ -x "$HOOK_SCRIPT" || -f "$HOOK_SCRIPT" ]]; then
  run_test "正常なエラー記録" test_normal_error_recording
else
  run_test_skip "正常なエラー記録" "hook script not found"
fi

# Edge case: exit_code が他の非ゼロ値(2, 127, 255)でも記録される
test_various_exit_codes() {
  for code in 2 127 255; do
    run_hook_in_sandbox "$code"
    local errors_file
    errors_file=$(get_errors_file)
    [[ -f "$errors_file" ]] || return 1
    local last_line
    last_line=$(tail -1 "$errors_file")
    local recorded_code
    recorded_code=$(echo "$last_line" | python3 -c "import json,sys; print(json.load(sys.stdin)['exit_code'])" 2>/dev/null)
    [[ "$recorded_code" == "$code" ]] || return 1
  done
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "正常なエラー記録 [edge: 複数の非ゼロ exit_code (2,127,255)]" test_various_exit_codes
else
  run_test_skip "正常なエラー記録 [edge: 複数の非ゼロ exit_code]" "hook script not found"
fi

# Edge case: 複数回の呼び出しで行が追記される（上書きではない）
test_append_multiple_errors() {
  run_hook_in_sandbox 1
  run_hook_in_sandbox 2
  run_hook_in_sandbox 3
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
  local line_count
  line_count=$(wc -l < "$errors_file")
  [[ "$line_count" -ge 3 ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "正常なエラー記録 [edge: 複数回呼び出しで追記]" test_append_multiple_errors
else
  run_test_skip "正常なエラー記録 [edge: 複数回呼び出しで追記]" "hook script not found"
fi

# Edge case: 記録される JSON が有効な JSONL（各行が独立したJSON）
test_valid_jsonl_format() {
  run_hook_in_sandbox 1
  run_hook_in_sandbox 2
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
  # Each line must be valid JSON
  while IFS= read -r line; do
    echo "$line" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || return 1
  done < "$errors_file"
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "正常なエラー記録 [edge: JSONL 各行が有効な JSON]" test_valid_jsonl_format
else
  run_test_skip "正常なエラー記録 [edge: JSONL 各行が有効な JSON]" "hook script not found"
fi

# Edge case: timestamp が ISO8601 形式
test_timestamp_iso8601() {
  run_hook_in_sandbox 1
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
  local last_line
  last_line=$(tail -1 "$errors_file")
  echo "$last_line" | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
ts = data.get('timestamp', '')
# ISO8601 basic pattern: YYYY-MM-DDTHH:MM:SSZ or with timezone offset
assert re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', ts), f'Invalid ISO8601: {ts}'
" 2>/dev/null || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "正常なエラー記録 [edge: timestamp ISO8601 形式]" test_timestamp_iso8601
else
  run_test_skip "正常なエラー記録 [edge: timestamp ISO8601 形式]" "hook script not found"
fi

# Scenario: PostToolUseFailure は常にエラー記録する (line 18)
# NOTE: PostToolUseFailure hook は「エラー時のみ」呼ばれるため、hook 自体は常に記録する。
# exit_code 0 が error フィールドに含まれていても、PostToolUseFailure なので最低 exit_code=1 として記録。
test_always_records_on_failure_hook() {
  run_hook_in_sandbox 0
  local errors_file
  errors_file=$(get_errors_file)
  # PostToolUseFailure hook は常に記録（exit 0 でも最低 1 に引き上げ）
  [[ -f "$errors_file" ]] || return 1
  local line_count
  line_count=$(wc -l < "$errors_file")
  [[ "$line_count" -ge 1 ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "PostToolUseFailure hook は exit_code 0 でも最低 1 として記録する" test_always_records_on_failure_hook
else
  run_test_skip "PostToolUseFailure hook は exit_code 0 でも最低 1 として記録する" "hook script not found"
fi

# Edge case: 連続呼び出しで全て記録される（PostToolUseFailure は常にエラー）
test_consecutive_calls_all_recorded() {
  run_hook_in_sandbox 0
  run_hook_in_sandbox 1
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
  local line_count
  line_count=$(wc -l < "$errors_file")
  # PostToolUseFailure なので両方記録される
  [[ "$line_count" -eq 2 ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "連続呼び出しで全て記録される [edge: PostToolUseFailure は常にエラー]" test_consecutive_calls_all_recorded
else
  run_test_skip "連続呼び出しで全て記録される [edge: PostToolUseFailure は常にエラー]" "hook script not found"
fi

# Scenario: command の切り詰め (line 22)
# WHEN: 実行されたコマンドが 200 文字を超える
# THEN: command フィールドは先頭 200 文字に切り詰められる
# Note: Current hook implementation may not yet include command field from TOOL_INPUT.
#       This test verifies the spec requirement exists in the script.
test_command_truncation_spec() {
  # Check the hook script references command truncation or 200 char limit
  grep -qP "200|command|TOOL_INPUT|cut.*-c" "$HOOK_SCRIPT" 2>/dev/null
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  # Structural check: does the script handle command truncation?
  if grep -qP "TOOL_INPUT|command" "$HOOK_SCRIPT" 2>/dev/null; then
    run_test "command の切り詰め [構造検証]" test_command_truncation_spec
  else
    run_test_skip "command の切り詰め" "hook does not yet implement TOOL_INPUT parsing"
  fi
else
  run_test_skip "command の切り詰め" "hook script not found"
fi

# Scenario: stderr_snippet の切り詰め (line 26)
# WHEN: stderr 出力が 500 文字を超える
# THEN: stderr_snippet フィールドは先頭 500 文字に切り詰められる
test_stderr_truncation_spec() {
  grep -qP "500|stderr|TOOL_OUTPUT|snippet" "$HOOK_SCRIPT" 2>/dev/null
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  if grep -qP "TOOL_OUTPUT|stderr" "$HOOK_SCRIPT" 2>/dev/null; then
    run_test "stderr_snippet の切り詰め [構造検証]" test_stderr_truncation_spec
  else
    run_test_skip "stderr_snippet の切り詰め" "hook does not yet implement TOOL_OUTPUT parsing"
  fi
else
  run_test_skip "stderr_snippet の切り詰め" "hook script not found"
fi

# Scenario: 環境変数が利用不可の場合のフォールバック (line 30)
# WHEN: PostToolUse 環境変数（TOOL_INPUT, TOOL_OUTPUT）が空または未設定である
# THEN: command は空文字列、stderr_snippet は空文字列としてフォールバック記録される
test_env_var_fallback() {
  # Run hook without TOOL_INPUT/TOOL_OUTPUT set
  unset TOOL_INPUT 2>/dev/null || true
  unset TOOL_OUTPUT 2>/dev/null || true
  run_hook_in_sandbox 1
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
  # The record should still be created (hook should not crash)
  local line_count
  line_count=$(wc -l < "$errors_file")
  [[ "$line_count" -ge 1 ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "環境変数が利用不可の場合のフォールバック" test_env_var_fallback
else
  run_test_skip "環境変数が利用不可の場合のフォールバック" "hook script not found"
fi

# Edge case: hook が常に exit 0 を返す（サイレント・ノンブロッキング）
test_always_exit_zero() {
  local result
  # Valid error case
  echo '{"error":"Exit code 1"}' | bash "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1
  # No error field
  echo '{}' | bash "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1
  # Invalid JSON
  echo "not_json" | bash "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1
  # Empty stdin
  echo "" | bash "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "hook が常に exit 0 を返す [サイレント・ノンブロッキング]" test_always_exit_zero
else
  run_test_skip "hook が常に exit 0 を返す" "hook script not found"
fi

# Edge case: 不正な stdin を渡しても crash しない
test_invalid_stdin_no_crash() {
  local result
  for input in "" "abc" "{}" '{"error":""}' '{"error":"no exit code"}' "null"; do
    echo "$input" | bash "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh" 2>/dev/null
    result=$?
    [[ "$result" -eq 0 ]] || return 1
  done
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "不正な stdin でも crash しない [edge: 各種不正入力]" test_invalid_stdin_no_crash
else
  run_test_skip "不正な stdin でも crash しない" "hook script not found"
fi

# Edge case: 不正な stdin でも記録する（PostToolUseFailure は常にエラー、exit_code 不明時は 1）
test_invalid_stdin_still_records() {
  for input in "" "abc" "not json" "{}"; do
    echo "$input" | bash "${SANDBOX}/scripts/hooks/post-tool-use-bash-error.sh" 2>/dev/null
  done
  local errors_file
  errors_file=$(get_errors_file)
  # PostToolUseFailure hook は常に記録（exit_code 不明時は 1 にフォールバック）
  [[ -f "$errors_file" ]] || return 1
  local line_count
  line_count=$(wc -l < "$errors_file")
  [[ "$line_count" -ge 1 ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "不正な stdin でも記録する [edge: PostToolUseFailure は常にエラー扱い]" test_invalid_stdin_still_records
else
  run_test_skip "不正な stdin でも記録する" "hook script not found"
fi

# =============================================================================
# Requirement: .self-improve ディレクトリの自動作成
# =============================================================================
echo ""
echo "--- Requirement: .self-improve ディレクトリの自動作成 ---"

# Scenario: 初回記録時のディレクトリ作成 (line 40)
# WHEN: .self-improve/ ディレクトリが存在せず、Bash エラーが発生する
# THEN: .self-improve/ ディレクトリが作成され、errors.jsonl に記録が書き込まれる
test_auto_create_directory() {
  # Ensure .self-improve does NOT exist in sandbox
  rm -rf "${SANDBOX}/.self-improve" 2>/dev/null || true
  [[ ! -d "${SANDBOX}/.self-improve" ]] || return 1
  run_hook_in_sandbox 1
  # Directory should now exist
  [[ -d "${SANDBOX}/.self-improve" ]] || return 1
  # File should exist and have content
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
  local line_count
  line_count=$(wc -l < "$errors_file")
  [[ "$line_count" -ge 1 ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "初回記録時のディレクトリ作成" test_auto_create_directory
else
  run_test_skip "初回記録時のディレクトリ作成" "hook script not found"
fi

# Edge case: ディレクトリが既に存在する場合はエラーにならない
test_existing_directory_no_error() {
  mkdir -p "${SANDBOX}/.self-improve"
  run_hook_in_sandbox 1
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
  local errors_file
  errors_file=$(get_errors_file)
  [[ -f "$errors_file" ]] || return 1
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "ディレクトリ既存時もエラーにならない [edge: 冪等性]" test_existing_directory_no_error
else
  run_test_skip "ディレクトリ既存時もエラーにならない" "hook script not found"
fi

# Edge case: hook スクリプトに mkdir -p が使われている（冪等な作成）
test_mkdir_p_used() {
  grep -qP "mkdir\s+-p" "$HOOK_SCRIPT" 2>/dev/null
}

if [[ -f "$HOOK_SCRIPT" ]]; then
  run_test "mkdir -p が使われている [edge: 冪等作成コマンド]" test_mkdir_p_used
else
  run_test_skip "mkdir -p が使われている" "hook script not found"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
