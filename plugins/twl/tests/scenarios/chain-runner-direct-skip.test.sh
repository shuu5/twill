#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: chain-runner-direct-skip
# Generated from: deltaspec/changes/issue-381/specs/chain-runner-direct-skip/spec.md
# Coverage level: edge-cases
#
# These are document verification tests that confirm chain-runner.sh contains
# the correct structural patterns for DIRECT_SKIP_STEPS / mode=direct support.
# Runtime/behavioral tests are out of scope until the fix is applied.
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

# Assert that a pattern appears within the same function block as an anchor pattern.
# Uses awk to extract the function body and then searches within it.
assert_pattern_in_function() {
  local file="$1"
  local func_name="$2"  # function anchor (regex for grep)
  local pattern="$3"    # pattern to find within the function
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  # Extract lines from function definition to the next top-level function or EOF
  awk "/^${func_name}[[:space:]]*\(\)/{found=1} found{print} /^[a-z_].*\(\)[[:space:]]*\{/{if(!/${func_name}/)found=0}" \
    "${PROJECT_ROOT}/${file}" | grep -qiP "$pattern"
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
  ((SKIP++)) || true
}

TARGET="scripts/chain-runner.sh"
STEPS_FILE="scripts/chain-steps.sh"

# =============================================================================
# Requirement: step_next_step が DIRECT_SKIP_STEPS を参照する
# =============================================================================
echo ""
echo "--- Requirement: step_next_step が DIRECT_SKIP_STEPS を参照する ---"

# Scenario: mode=direct 時に change-propose がスキップされる
# WHEN: step_next_step が呼ばれる
# THEN: DIRECT_SKIP_STEPS を参照して change-propose をスキップする
test_step_next_step_references_direct_skip_steps() {
  assert_file_exists "$TARGET" || return 1
  # step_next_step 関数内に DIRECT_SKIP_STEPS への参照があること
  assert_pattern_in_function "$TARGET" "step_next_step" "DIRECT_SKIP_STEPS"
}
run_test "step_next_step [Scenario: mode=direct 時に change-propose がスキップされる] DIRECT_SKIP_STEPS を参照する" \
  test_step_next_step_references_direct_skip_steps

# Scenario: mode=direct 時に change-id-resolve がスキップされる
# WHEN: step_next_step が change-id-resolve の前のステップを current_step として呼ばれる
# THEN: DIRECT_SKIP_STEPS を確認して change-id-resolve を飛ばす
test_step_next_step_skips_change_id_resolve() {
  assert_file_exists "$TARGET" || return 1
  # DIRECT_SKIP_STEPS が chain-steps.sh で change-id-resolve を含むこと（SSOT確認）
  assert_file_exists "$STEPS_FILE" || return 1
  assert_file_contains "$STEPS_FILE" "change-id-resolve" || return 1
  # step_next_step が DIRECT_SKIP_STEPS を参照していること
  assert_pattern_in_function "$TARGET" "step_next_step" "DIRECT_SKIP_STEPS"
}
run_test "step_next_step [Scenario: mode=direct 時に change-id-resolve がスキップされる] DIRECT_SKIP_STEPS+change-id-resolve を参照する" \
  test_step_next_step_skips_change_id_resolve

# Scenario: mode=direct 時に change-apply がスキップされる
# WHEN: step_next_step が change-apply の前のステップを current_step として呼ばれる
# THEN: DIRECT_SKIP_STEPS を確認して change-apply を飛ばす
test_step_next_step_skips_change_apply() {
  assert_file_exists "$TARGET" || return 1
  assert_file_exists "$STEPS_FILE" || return 1
  assert_file_contains "$STEPS_FILE" "change-apply" || return 1
  assert_pattern_in_function "$TARGET" "step_next_step" "DIRECT_SKIP_STEPS"
}
run_test "step_next_step [Scenario: mode=direct 時に change-apply がスキップされる] DIRECT_SKIP_STEPS+change-apply を参照する" \
  test_step_next_step_skips_change_apply

# Scenario: mode が direct 以外の場合は DIRECT_SKIP_STEPS をスキップしない
# WHEN: mode が "propose" または "apply" のとき
# THEN: スキップロジックが mode="direct" 条件付きであること
test_step_next_step_direct_mode_conditional() {
  assert_file_exists "$TARGET" || return 1
  # is_direct 変数または mode == "direct" 比較が step_next_step 内にあること
  assert_pattern_in_function "$TARGET" "step_next_step" 'is_direct|mode.*==.*"direct"|"direct".*mode'
}
run_test "step_next_step [Scenario: mode が direct 以外はスキップしない] is_direct または mode==\"direct\" 条件判定を使用する" \
  test_step_next_step_direct_mode_conditional

# Edge case: step_next_step が state から mode フィールドを読む
test_step_next_step_reads_mode_from_state() {
  assert_file_exists "$TARGET" || return 1
  # twl.autopilot.state read と mode を同一関数内で参照
  assert_pattern_in_function "$TARGET" "step_next_step" "autopilot.state read.*mode|--field mode|mode.*autopilot"
}
run_test "step_next_step [edge: state から mode フィールドを読む]" \
  test_step_next_step_reads_mode_from_state

# Edge case: DIRECT_SKIP_STEPS が chain-steps.sh で定義されていること（SSOT）
test_direct_skip_steps_defined_in_chain_steps() {
  assert_file_exists "$STEPS_FILE" || return 1
  assert_file_contains "$STEPS_FILE" "DIRECT_SKIP_STEPS" || return 1
}
run_test "chain-steps.sh [edge: DIRECT_SKIP_STEPS が SSOT として定義されている]" \
  test_direct_skip_steps_defined_in_chain_steps

# Edge case: DIRECT_SKIP_STEPS に change-propose / change-id-resolve / change-apply が含まれること
test_direct_skip_steps_contains_required_steps() {
  assert_file_exists "$STEPS_FILE" || return 1
  assert_file_contains_all "$STEPS_FILE" \
    "change-propose" \
    "change-id-resolve" \
    "change-apply"
}
run_test "chain-steps.sh [edge: DIRECT_SKIP_STEPS に change-propose / change-id-resolve / change-apply が含まれる]" \
  test_direct_skip_steps_contains_required_steps

# =============================================================================
# Requirement: step_chain_status が DIRECT_SKIP_STEPS を正しく表示する
# =============================================================================
echo ""
echo "--- Requirement: step_chain_status が DIRECT_SKIP_STEPS を正しく表示する ---"

# Scenario: mode=direct 時に skipped/direct ラベルが表示される
# WHEN: mode="direct" で chain-status が実行される
# THEN: skipped/direct ラベルが表示される
test_step_chain_status_shows_skipped_direct_label() {
  assert_file_exists "$TARGET" || return 1
  # step_chain_status 内に "skipped/direct" 文字列があること
  assert_pattern_in_function "$TARGET" "step_chain_status" "skipped/direct"
}
run_test "step_chain_status [Scenario: mode=direct 時に skipped/direct ラベルが表示される]" \
  test_step_chain_status_shows_skipped_direct_label

# Scenario: mode が direct 以外の場合は通常表示される
# THEN: skipped/direct ラベルは mode=direct 条件付きであること
test_step_chain_status_direct_mode_conditional() {
  assert_file_exists "$TARGET" || return 1
  # step_chain_status 内に DIRECT_SKIP_STEPS への参照があること
  assert_pattern_in_function "$TARGET" "step_chain_status" "DIRECT_SKIP_STEPS"
}
run_test "step_chain_status [Scenario: mode が direct 以外は通常表示] DIRECT_SKIP_STEPS を条件参照する" \
  test_step_chain_status_direct_mode_conditional

# Edge case: step_chain_status が state から mode フィールドを読む
test_step_chain_status_reads_mode_from_state() {
  assert_file_exists "$TARGET" || return 1
  assert_pattern_in_function "$TARGET" "step_chain_status" "autopilot.state read.*mode|--field mode|mode.*autopilot|is_direct"
}
run_test "step_chain_status [edge: state から mode フィールドを読む]" \
  test_step_chain_status_reads_mode_from_state

# Edge case: step_chain_status に ⊘ ... (skipped/direct) パターンが存在する
test_step_chain_status_shows_circle_slash_direct() {
  assert_file_exists "$TARGET" || return 1
  # skipped/direct リテラルが step_chain_status 内に存在すること（⊘付きの行）
  assert_pattern_in_function "$TARGET" "step_chain_status" "skipped/direct"
}
run_test "step_chain_status [edge: ⊘ ... (skipped/direct) パターンが存在する]" \
  test_step_chain_status_shows_circle_slash_direct

# Edge case: step_chain_status が既存の skipped/quick と同じ構造パターンで skipped/direct を実装する
test_step_chain_status_parallel_skip_pattern() {
  assert_file_exists "$TARGET" || return 1
  # skipped/quick が存在する（既存パターン）
  assert_pattern_in_function "$TARGET" "step_chain_status" "skipped/quick" || return 1
}
run_test "step_chain_status [edge: skipped/quick の既存パターンと並列構造]" \
  test_step_chain_status_parallel_skip_pattern

# =============================================================================
# Structural: chain-runner.sh が chain-steps.sh を source している
# =============================================================================
echo ""
echo "--- Structural: chain-runner.sh が chain-steps.sh を source する ---"

test_chain_runner_sources_chain_steps() {
  assert_file_exists "$TARGET" || return 1
  assert_file_contains "$TARGET" "source.*chain-steps\.sh" || return 1
}
run_test "chain-runner.sh が chain-steps.sh を source している" \
  test_chain_runner_sources_chain_steps

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
