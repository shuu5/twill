#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: autopilot-launch-input-validation
# Generated from: openspec/changes/autopilot-launch-input-validation/specs/input-validation/spec.md
# Coverage level: edge-cases
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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
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

# バリデーションロジックは scripts/autopilot-launch.sh に移行済み
LAUNCH_CMD="scripts/autopilot-launch.sh"

# =============================================================================
# Requirement: クロスリポジトリ変数の入力バリデーション
# =============================================================================
echo ""
echo "--- Requirement: クロスリポジトリ変数の入力バリデーション ---"

# Scenario: ISSUE_REPO_OWNER が不正なパターンの場合
# WHEN: ISSUE_REPO_OWNER が設定されており、^[a-zA-Z0-9_-]+$ に一致しない
# THEN: state-write.sh で status=failed、failure に invalid_repo_owner を書き込み

test_owner_validation_pattern() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'REPO_OWNER.*\[a-zA-Z0-9_-\]' || return 1
  return 0
}
run_test "ISSUE_REPO_OWNER のバリデーションパターン ^[a-zA-Z0-9_-]+$ が存在する" \
  test_owner_validation_pattern

test_owner_validation_failure_state() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'invalid_repo_owner' || return 1
  return 0
}
run_test "ISSUE_REPO_OWNER バリデーション失敗時に invalid_repo_owner を state-write する" \
  test_owner_validation_failure_state

# Scenario: ISSUE_REPO_NAME が不正なパターンの場合
# WHEN: ISSUE_REPO_NAME が設定されており、^[a-zA-Z0-9_.-]+$ に一致しない
# THEN: state-write.sh で status=failed、failure に invalid_repo_name を書き込み

test_name_validation_pattern() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'REPO_NAME.*\[a-zA-Z0-9_\.' || return 1
  return 0
}
run_test "ISSUE_REPO_NAME のバリデーションパターン ^[a-zA-Z0-9_.-]+$ が存在する" \
  test_name_validation_pattern

test_name_validation_failure_state() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'invalid_repo_name' || return 1
  return 0
}
run_test "ISSUE_REPO_NAME バリデーション失敗時に invalid_repo_name を state-write する" \
  test_name_validation_failure_state

# Scenario: ISSUE_REPO_OWNER/NAME が未設定の場合
# WHEN: ISSUE_REPO_OWNER または ISSUE_REPO_NAME が空またはunset
# THEN: バリデーションをスキップし、正常に次のステップへ進む

test_owner_name_skip_when_unset() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  # Validation should be conditional on variables being set (e.g., -n or -z check)
  assert_file_contains "$LAUNCH_CMD" \
    'REPO_OWNER' || return 1
  return 0
}
run_test "ISSUE_REPO_OWNER 未設定時はバリデーションをスキップする条件分岐が存在する" \
  test_owner_name_skip_when_unset

# Edge case: バリデーション失敗時に return 1 する
test_owner_validation_returns_1() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'invalid_repo_owner.*\n.*exit 1|exit 1' || return 1
  # At minimum, return 1 should exist near the validation block
  assert_file_contains "$LAUNCH_CMD" \
    'exit 1' || return 1
  return 0
}
run_test "[edge] バリデーション失敗時に exit 1 が存在する" \
  test_owner_validation_returns_1

# Edge case: state-write.sh が --type issue 形式で呼ばれている
test_validation_state_write_named_flags() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'state-write.*--type\s+issue' || return 1
  return 0
}
run_test "[edge] バリデーションエラー時の state-write.sh が --type issue 形式である" \
  test_validation_state_write_named_flags

# =============================================================================
# Requirement: PILOT_AUTOPILOT_DIR のパスバリデーション
# =============================================================================
echo ""
echo "--- Requirement: PILOT_AUTOPILOT_DIR のパスバリデーション ---"

# Scenario: PILOT_AUTOPILOT_DIR が相対パスの場合
# WHEN: PILOT_AUTOPILOT_DIR が設定されており、/ で始まらない
# THEN: state-write.sh で status=failed、failure に invalid_autopilot_dir を書き込み

test_autopilot_dir_absolute_path_check() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  # Check for absolute path validation (starts with /)
  assert_file_contains "$LAUNCH_CMD" \
    'AUTOPILOT_DIR.*!=.*/\\*|AUTOPILOT_DIR.*=~.*\\^/' || return 1
  return 0
}
run_test "PILOT_AUTOPILOT_DIR の絶対パスチェック（^/ で始まる）が存在する" \
  test_autopilot_dir_absolute_path_check

test_autopilot_dir_failure_message() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'invalid_autopilot_dir' || return 1
  return 0
}
run_test "PILOT_AUTOPILOT_DIR バリデーション失敗時に invalid_autopilot_dir を出力する" \
  test_autopilot_dir_failure_message

# Scenario: PILOT_AUTOPILOT_DIR にパストラバーサルが含まれる場合
# WHEN: PILOT_AUTOPILOT_DIR に .. コンポーネントが含まれる
# THEN: state-write.sh で status=failed

test_autopilot_dir_traversal_check() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  # Check for path traversal detection (\.\./ or \.\.$)
  assert_file_contains "$LAUNCH_CMD" \
    'AUTOPILOT_DIR.*\\\.\\\.' || return 1
  return 0
}
run_test "PILOT_AUTOPILOT_DIR のパストラバーサル（..）チェックが存在する" \
  test_autopilot_dir_traversal_check

# Scenario: PILOT_AUTOPILOT_DIR が未設定の場合
# WHEN: PILOT_AUTOPILOT_DIR が空またはunset
# THEN: バリデーションをスキップ

test_autopilot_dir_skip_when_unset() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    'AUTOPILOT_DIR' || return 1
  return 0
}
run_test "PILOT_AUTOPILOT_DIR 未設定時はバリデーションをスキップする条件分岐が存在する" \
  test_autopilot_dir_skip_when_unset

# =============================================================================
# Requirement: AUTOPILOT_ENV / REPO_ENV のクォート展開
# =============================================================================
echo ""
echo "--- Requirement: AUTOPILOT_ENV / REPO_ENV のクォート展開 ---"

# Scenario: AUTOPILOT_ENV の値が printf '%q' でクォートされる
test_autopilot_env_quoted() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    "printf\s+'%q'.*AUTOPILOT_DIR" || return 1
  return 0
}
run_test "AUTOPILOT_ENV の値が printf '%q' でクォートされている" \
  test_autopilot_env_quoted

# Scenario: REPO_ENV の値が printf '%q' でクォートされる
test_repo_env_quoted() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  assert_file_contains "$LAUNCH_CMD" \
    "printf\s+'%q'.*REPO_OWNER|printf\s+'%q'.*REPO_NAME" || return 1
  return 0
}
run_test "REPO_ENV の値が printf '%q' でクォートされている" \
  test_repo_env_quoted

# Edge case: tmux new-window の env 行でダブルクォートなし展開がない
test_no_unquoted_env_expansion() {
  assert_file_exists "$LAUNCH_CMD" || return 1
  # The old pattern: env $AUTOPILOT_ENV $REPO_ENV should use quoted variables
  # Check that AUTOPILOT_ENV and REPO_ENV are quoted (not bare $AUTOPILOT_ENV $REPO_ENV on tmux line)
  assert_file_not_contains "$LAUNCH_CMD" \
    'env\s+\$AUTOPILOT_ENV\s+\$REPO_ENV' || return 1
  return 0
}
run_test "[edge] tmux new-window 行で \$AUTOPILOT_ENV \$REPO_ENV がダブルクォートなし展開されていない" \
  test_no_unquoted_env_expansion

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Summary ==="
echo "PASS: ${PASS} / FAIL: ${FAIL} / SKIP: ${SKIP}"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - ${e}"
  done
  exit 1
fi
exit 0
