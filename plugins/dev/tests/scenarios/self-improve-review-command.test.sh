#!/usr/bin/env bash
# =============================================================================
# Document/Structure Verification Tests: self-improve-review-command.md
# Generated from: openspec/changes/b-7-self-improve-review-hook/specs/self-improve-review-command.md
# Coverage level: edge-cases
#
# Note: self-improve-review is a markdown-based AI command (COMMAND.md).
# These tests verify structural correctness: file existence, required sections,
# deps.yaml registration, and output format compatibility.
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_dir_exists() {
  local dir="$1"
  [[ -d "${PROJECT_ROOT}/${dir}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
  $func || result=$?
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
# Requirement: self-improve-review コマンド
# =============================================================================
echo ""
echo "--- Requirement: self-improve-review コマンド ---"

COMMAND_FILE="commands/self-improve-review.md"

# Scenario: エラーログなしの終了 (line 16)
# WHEN: .self-improve/errors.jsonl が存在しないまたは空である
# THEN: 「エラーログなし」とメッセージを表示して正常終了する
# Structural verification: COMMAND.md にエラーログなし時の挙動が記載されている
test_command_no_error_log_handling() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "errors\.jsonl.*存在しない|エラーログ.*なし|ログ.*空|no.*error.*log"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "エラーログなしの終了 [COMMAND.md 記載検証]" test_command_no_error_log_handling
else
  run_test_skip "エラーログなしの終了" "COMMAND.md not yet created"
fi

# Edge case: .self-improve/errors.jsonl パスが正確に参照されている
test_command_errors_path_accurate() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "\.self-improve/errors\.jsonl"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "エラーログなし [edge: errors.jsonl パス正確]" test_command_errors_path_accurate
else
  run_test_skip "エラーログなし [edge: errors.jsonl パス正確]" "COMMAND.md not yet created"
fi

# Scenario: エラーサマリー表示 (line 20)
# WHEN: .self-improve/errors.jsonl に 1 件以上のエラーが記録されている
# THEN: コマンド別・exit_code 別にグループ化したサマリーテーブルが表示される
test_command_error_summary() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains_all "$COMMAND_FILE" \
    "サマリー|summary|集計|テーブル" \
    "グループ|group|exit_code|コマンド別"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "エラーサマリー表示 [COMMAND.md 記載検証]" test_command_error_summary
else
  run_test_skip "エラーサマリー表示" "COMMAND.md not yet created"
fi

# Edge case: 集計の軸（コマンド別 + exit_code別）が両方明示されている
test_command_summary_axes() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "コマンド別|command.*別|by.*command" || return 1
  assert_file_contains "$COMMAND_FILE" "exit_code.*別|exit.code|エラーコード"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "エラーサマリー [edge: 集計軸が明示]" test_command_summary_axes
else
  run_test_skip "エラーサマリー [edge: 集計軸が明示]" "COMMAND.md not yet created"
fi

# Scenario: ユーザー選択による構造化 (line 24)
# WHEN: ユーザーがサマリーから特定のエラーグループを選択する
# THEN: 選択されたエラーについて会話コンテキストを参照し問題が構造化される
test_command_user_selection() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains_all "$COMMAND_FILE" \
    "選択|select|AskUser" \
    "構造化|structure|問題"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "ユーザー選択による構造化 [COMMAND.md 記載検証]" test_command_user_selection
else
  run_test_skip "ユーザー選択による構造化" "COMMAND.md not yet created"
fi

# Edge case: AskUserQuestion が明示的に使用されている
test_command_ask_user_question() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "AskUser"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "ユーザー選択 [edge: AskUserQuestion 使用]" test_command_ask_user_question
else
  run_test_skip "ユーザー選択 [edge: AskUserQuestion 使用]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: explore-summary.md 出力
# =============================================================================
echo ""
echo "--- Requirement: explore-summary.md 出力 ---"

# Scenario: explore-summary.md の生成 (line 32)
# WHEN: ユーザーがエラーの構造化を完了する
# THEN: .controller-issue/explore-summary.md が co-issue Phase 1 互換形式で生成される
test_command_explore_summary_output() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains_all "$COMMAND_FILE" \
    "explore-summary\.md|explore.summary" \
    "\.controller-issue|controller.issue"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "explore-summary.md の生成 [COMMAND.md 記載検証]" test_command_explore_summary_output
else
  run_test_skip "explore-summary.md の生成" "COMMAND.md not yet created"
fi

# Edge case: co-issue Phase 1 互換性が明示されている
test_command_coissue_phase1_compat() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "Phase\s*1|co-issue.*互換|co-issue.*compatible"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "explore-summary [edge: co-issue Phase 1 互換明示]" test_command_coissue_phase1_compat
else
  run_test_skip "explore-summary [edge: co-issue Phase 1 互換明示]" "COMMAND.md not yet created"
fi

# Edge case: 出力パスが .controller-issue/explore-summary.md で正確
test_command_explore_summary_path() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "\.controller-issue/explore-summary\.md"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "explore-summary [edge: 出力パス正確]" test_command_explore_summary_path
else
  run_test_skip "explore-summary [edge: 出力パス正確]" "COMMAND.md not yet created"
fi

# Scenario: co-issue 続行の確認 (line 36)
# WHEN: explore-summary.md の生成が完了する
# THEN: 「co-issue を呼び出して Issue 化を続けますか？」とユーザーに確認する
test_command_coissue_continuation() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "co-issue.*呼び出|co-issue.*続|Issue化.*続|continue.*co-issue"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "co-issue 続行の確認 [COMMAND.md 記載検証]" test_command_coissue_continuation
else
  run_test_skip "co-issue 続行の確認" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: エラーログクリアオプション
# =============================================================================
echo ""
echo "--- Requirement: エラーログクリアオプション ---"

# Scenario: エラーログのクリア (line 44)
# WHEN: ユーザーがクリアオプションを選択する
# THEN: .self-improve/errors.jsonl が削除される
test_command_clear_option() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains_all "$COMMAND_FILE" \
    "クリア|clear|削除|delete" \
    "errors\.jsonl"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "エラーログのクリア [COMMAND.md 記載検証]" test_command_clear_option
else
  run_test_skip "エラーログのクリア" "COMMAND.md not yet created"
fi

# Edge case: クリアがオプション提示（ユーザー確認あり）であること
test_command_clear_with_confirmation() {
  assert_file_exists "$COMMAND_FILE" || return 1
  assert_file_contains "$COMMAND_FILE" "オプション|選択|confirm|確認"
}

if assert_file_exists "$COMMAND_FILE" 2>/dev/null; then
  run_test "エラーログクリア [edge: ユーザー確認あり]" test_command_clear_with_confirmation
else
  run_test_skip "エラーログクリア [edge: ユーザー確認あり]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: deps.yaml 登録
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml 登録 ---"

DEPS_FILE="deps.yaml"

# Scenario: deps.yaml への登録 (line 52)
# WHEN: self-improve-review コマンドが追加される
# THEN: deps.yaml の commands セクションに type: atomic、path が登録される
test_depsyaml_registration() {
  assert_file_exists "$DEPS_FILE" || return 1
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${DEPS_FILE}') as f:
    data = yaml.safe_load(f)
commands = data.get('commands', {})
if isinstance(commands, dict) and 'self-improve-review' in commands:
    cmd = commands['self-improve-review']
    assert cmd.get('type') == 'atomic', f'type should be atomic, got {cmd.get(\"type\")}'
    assert 'self-improve-review' in cmd.get('path', ''), f'path should contain self-improve-review'
    sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

# Always check deps.yaml (it exists from the start)
if python3 -c "import yaml" 2>/dev/null; then
  run_test "deps.yaml への登録" test_depsyaml_registration
else
  run_test_skip "deps.yaml への登録" "python3 yaml module not available"
fi

# Edge case: type が atomic であること
test_depsyaml_type_atomic() {
  assert_file_exists "$DEPS_FILE" || return 1
  assert_file_contains "$DEPS_FILE" "self-improve-review" || return 1
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${DEPS_FILE}') as f:
    data = yaml.safe_load(f)
commands = data.get('commands', {})
if isinstance(commands, dict) and 'self-improve-review' in commands:
    assert commands['self-improve-review'].get('type') == 'atomic'
    sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

if python3 -c "import yaml" 2>/dev/null; then
  run_test "deps.yaml [edge: type が atomic]" test_depsyaml_type_atomic
else
  run_test_skip "deps.yaml [edge: type が atomic]" "python3 yaml module not available"
fi

# Edge case: path が commands/self-improve-review.md であること
test_depsyaml_path_correct() {
  assert_file_exists "$DEPS_FILE" || return 1
  assert_file_contains "$DEPS_FILE" "commands/self-improve-review\.md"
}

run_test "deps.yaml [edge: path が正確]" test_depsyaml_path_correct

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
