#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: all-pass-check.md
# Generated from: openspec/changes/b-5-pr-cycle-merge-gate-chain-driven/specs/all-pass-check.md
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

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
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

yaml_get() {
  local file="$1"
  local expr="$2"
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    data = yaml.safe_load(f)
${expr}
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

DEPS_YAML="deps.yaml"
ALL_PASS_CHECK_CMD="commands/all-pass-check/COMMAND.md"
STATE_WRITE_SCRIPT="scripts/state-write.sh"

# =============================================================================
# Requirement: all-pass-check autopilot-first 簡素化
# =============================================================================
echo ""
echo "--- Requirement: all-pass-check autopilot-first 簡素化 ---"

# Scenario: 全ステップ PASS (line 8)
# WHEN: pr-cycle の全ステップ（verify, review, test, visual）が PASS
# THEN: issue-{N}.json の status を merge-ready に遷移する（state-write.sh 経由）
# AND: Pilot が merge-gate を実行する

test_all_pass_check_exists() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  return 0
}
run_test "all-pass-check COMMAND.md が存在する" test_all_pass_check_exists

test_all_pass_check_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
all_entries = {}
for section in ['commands', 'skills', 'scripts']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

entry = all_entries.get('all-pass-check')
if entry is None:
    sys.exit(1)
if not isinstance(entry, dict):
    sys.exit(1)
if entry.get('type') != 'atomic':
    print(f'type={entry.get(\"type\")} (expected atomic)', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "all-pass-check が deps.yaml に type: atomic で登録されている" test_all_pass_check_registered

test_all_pass_check_merge_ready_transition() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(merge.ready|merge-ready)' || return 1
  return 0
}
run_test "all-pass-check に merge-ready 遷移が記述されている" test_all_pass_check_merge_ready_transition

test_all_pass_check_uses_state_write() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(state-write|state.write)' || return 1
  return 0
}
run_test "all-pass-check が state-write.sh を使用する記述がある" test_all_pass_check_uses_state_write

# Edge case: state-write.sh が merge-ready 状態をサポートしている
test_state_write_supports_merge_ready() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" '(merge.ready|merge-ready)' || return 1
  return 0
}
run_test "state-write.sh [edge: merge-ready 状態をサポート]" test_state_write_supports_merge_ready

# Edge case: all-pass-check が全ステップ確認をする旨の記述
test_all_pass_check_verifies_all_steps() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(全.*PASS|all.*pass|ステップ|step|verify|review|test|visual)' || return 1
  return 0
}
run_test "all-pass-check [edge: 全ステップ確認の記述がある]" test_all_pass_check_verifies_all_steps

# Scenario: いずれかのステップ FAIL (line 13)
# WHEN: pr-cycle のいずれかのステップが FAIL
# THEN: issue-{N}.json の status を failed に遷移する
# AND: 失敗ステップと理由が issue-{N}.json の結果フィールドに記録される

test_all_pass_check_fail_transition() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(failed|fail)' || return 1
  return 0
}
run_test "all-pass-check に failed 遷移が記述されている" test_all_pass_check_fail_transition

test_all_pass_check_records_failure_reason() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(理由|reason|失敗.*ステップ|failure|記録|record)' || return 1
  return 0
}
run_test "all-pass-check に失敗理由の記録が記述されている" test_all_pass_check_records_failure_reason

# Edge case: state-write.sh が failed 状態をサポートしている
test_state_write_supports_failed() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" '(failed)' || return 1
  return 0
}
run_test "state-write.sh [edge: failed 状態をサポート]" test_state_write_supports_failed

# =============================================================================
# Requirement: --auto-merge 分岐コード廃止 (REMOVED)
# =============================================================================
echo ""
echo "--- Requirement: --auto-merge 分岐コード廃止 (REMOVED) ---"

# Scenario: --auto-merge コードの不在 (line 25)
# WHEN: all-pass-check / auto-merge の実装を検査する
# THEN: --auto-merge フラグの解析、AUTO_MERGE 変数、.merge-ready マーカーファイルの読み書き、
#       DEV_AUTOPILOT_SESSION チェックが存在しない

test_no_auto_merge_flag() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_not_contains "$ALL_PASS_CHECK_CMD" '--auto-merge' || return 1
  return 0
}
run_test "all-pass-check に --auto-merge フラグがない" test_no_auto_merge_flag

test_no_auto_merge_variable() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_not_contains "$ALL_PASS_CHECK_CMD" 'AUTO_MERGE' || return 1
  return 0
}
run_test "all-pass-check に AUTO_MERGE 変数がない" test_no_auto_merge_variable

test_no_dev_autopilot_session() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_not_contains "$ALL_PASS_CHECK_CMD" 'DEV_AUTOPILOT_SESSION' || return 1
  return 0
}
run_test "all-pass-check に DEV_AUTOPILOT_SESSION がない" test_no_dev_autopilot_session

# Edge case: プロジェクト全体で --auto-merge の残骸がない
test_no_auto_merge_anywhere() {
  # Check pr-cycle related commands for --auto-merge remnants (workflow-setup is excluded as it legitimately uses the flag)
  if grep -rP '\-\-auto-merge' "${PROJECT_ROOT}/commands/all-pass-check/" "${PROJECT_ROOT}/commands/merge-gate/" "${PROJECT_ROOT}/skills/workflow-pr-cycle/" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "--auto-merge [edge: commands/ skills/ にも残骸がない]" test_no_auto_merge_anywhere

# Edge case: DEV_AUTOPILOT_SESSION がプロジェクト全体で使われていない
test_no_dev_autopilot_session_anywhere() {
  if grep -rP 'DEV_AUTOPILOT_SESSION' "${PROJECT_ROOT}/commands/" "${PROJECT_ROOT}/skills/" "${PROJECT_ROOT}/scripts/" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "DEV_AUTOPILOT_SESSION [edge: プロジェクト全体で不在]" test_no_dev_autopilot_session_anywhere

# =============================================================================
# Requirement: マーカーファイル廃止 (REMOVED)
# =============================================================================
echo ""
echo "--- Requirement: マーカーファイル廃止 (REMOVED) ---"

# Scenario: マーカーファイルの不在 (line 32)
# WHEN: pr-cycle / merge-gate の実装を検査する
# THEN: .done, .fail, .merge-ready 等のマーカーファイルの作成・読み取りコードが存在しない
# AND: 状態遷移は全て state-write.sh 経由で issue-{N}.json に記録される

test_no_done_marker() {
  # Check commands/ skills/ scripts/ for .done marker file references
  if grep -rP '\.done' "${PROJECT_ROOT}/commands/all-pass-check/" "${PROJECT_ROOT}/skills/merge-gate/" 2>/dev/null | grep -qvP '(#|comment)'; then
    return 1
  fi
  return 0
}
run_test "all-pass-check / merge-gate に .done マーカー参照がない" test_no_done_marker

test_no_fail_marker() {
  if grep -rP '\.fail\b' "${PROJECT_ROOT}/commands/all-pass-check/" "${PROJECT_ROOT}/skills/merge-gate/" 2>/dev/null | grep -qvP '(#|comment)'; then
    return 1
  fi
  return 0
}
run_test "all-pass-check / merge-gate に .fail マーカー参照がない" test_no_fail_marker

test_no_merge_ready_marker() {
  # .merge-ready as a file (not as a status string)
  if grep -rP 'touch.*\.merge-ready|cat.*\.merge-ready|test\s.*\.merge-ready|\-f.*\.merge-ready' \
    "${PROJECT_ROOT}/commands/all-pass-check/" "${PROJECT_ROOT}/skills/merge-gate/" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "all-pass-check / merge-gate に .merge-ready マーカーファイル操作がない" test_no_merge_ready_marker

# Edge case: state-write.sh が issue-{N}.json の状態遷移を管理していることの確認
test_state_write_manages_issue_json() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" '(issue.*json|issue-.*\.json)' || return 1
  return 0
}
run_test "state-write.sh [edge: issue-{N}.json を管理する記述がある]" test_state_write_manages_issue_json

# Edge case: state-write.sh に状態遷移バリデーションがある
test_state_write_has_transition_validation() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" '(valid.*transition|遷移.*バリデーション|transition.*check|allowed|invalid.*state)' || return 1
  return 0
}
run_test "state-write.sh [edge: 状態遷移バリデーションがある]" test_state_write_has_transition_validation

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
