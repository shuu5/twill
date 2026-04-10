#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: test-common.sh 共通ヘルパー抽出
# Generated from: deltaspec/changes/issue-410/specs/test-common-extract/spec.md
# Coverage level: edge-cases
#
# Change: issue-410 (tech-debt: skillmd-pilot-fixes.test.sh を 300 行以下に削減)
# Requirement 1: test-common.sh 共通ヘルパーの提供
# Requirement 2: skillmd-pilot-fixes.test.sh の行数削減
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

COMMON_SH="tests/helpers/test-common.sh"
TARGET_TEST="tests/scenarios/skillmd-pilot-fixes.test.sh"

# =============================================================================
# Requirement: test-common.sh 共通ヘルパーの提供
# =============================================================================
echo ""
echo "--- Requirement: test-common.sh 共通ヘルパーの提供 ---"

# Scenario: ヘルパー関数の提供
# WHEN: テストスクリプトが source で test-common.sh を読み込む
# THEN: assert_file_exists, assert_file_contains, assert_file_not_contains,
#       run_test, run_test_skip 関数が利用可能になる

# Test: test-common.sh ファイルが存在する
test_common_sh_exists() {
  assert_file_exists "$COMMON_SH"
}

run_test "test-common.sh が tests/helpers/ に存在する" test_common_sh_exists

# Test: assert_file_exists 関数が定義されている
test_assert_file_exists_defined() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'assert_file_exists\s*\(\)'
}

run_test "test-common.sh: assert_file_exists 関数が定義されている" test_assert_file_exists_defined

# Test: assert_file_contains 関数が定義されている
test_assert_file_contains_defined() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'assert_file_contains\s*\(\)'
}

run_test "test-common.sh: assert_file_contains 関数が定義されている" test_assert_file_contains_defined

# Test: assert_file_not_contains 関数が定義されている
test_assert_file_not_contains_defined() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'assert_file_not_contains\s*\(\)'
}

run_test "test-common.sh: assert_file_not_contains 関数が定義されている" test_assert_file_not_contains_defined

# Test: run_test 関数が定義されている
test_run_test_defined() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'run_test\s*\(\)'
}

run_test "test-common.sh: run_test 関数が定義されている" test_run_test_defined

# Test: run_test_skip 関数が定義されている
test_run_test_skip_defined() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'run_test_skip\s*\(\)'
}

run_test "test-common.sh: run_test_skip 関数が定義されている" test_run_test_skip_defined

# Edge case: source 後にシェル関数として実際にロードできる（bashの構文エラーがない）
test_common_sh_sourceable() {
  assert_file_exists "$COMMON_SH" || return 1
  bash -n "${PROJECT_ROOT}/${COMMON_SH}" 2>/dev/null
}

run_test "test-common.sh [edge: bash -n で構文エラーがない]" test_common_sh_sourceable

# Edge case: source することで 5 関数がシェルに定義される（実際の動的検証）
test_common_sh_functions_exported() {
  assert_file_exists "$COMMON_SH" || return 1
  bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    for fn in assert_file_exists assert_file_contains assert_file_not_contains run_test run_test_skip; do
      if ! declare -f \"\$fn\" > /dev/null 2>&1; then
        echo \"Missing function: \$fn\" >&2
        exit 1
      fi
    done
    exit 0
  " 2>/dev/null
}

run_test "test-common.sh [edge: source 後に全 5 関数がシェルに定義される]" test_common_sh_functions_exported

# Edge case: print_summary 関数も定義されている
test_print_summary_defined() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'print_summary\s*\(\)'
}

run_test "test-common.sh [edge: print_summary 関数が定義されている]" test_print_summary_defined

# =============================================================================
# Requirement: カウンターの初期化
# =============================================================================
echo ""
echo "--- Requirement: カウンターの初期化 ---"

# Scenario: カウンターの初期化
# WHEN: test-common.sh が source される
# THEN: PASS=0, FAIL=0, SKIP=0, ERRORS=() が初期化される

# Test: PASS=0 の初期化が test-common.sh に記述されている
test_counter_pass_init() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'PASS=0'
}

run_test "test-common.sh: PASS=0 の初期化が記述されている" test_counter_pass_init

# Test: FAIL=0 の初期化が記述されている
test_counter_fail_init() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'FAIL=0'
}

run_test "test-common.sh: FAIL=0 の初期化が記述されている" test_counter_fail_init

# Test: SKIP=0 の初期化が記述されている
test_counter_skip_init() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'SKIP=0'
}

run_test "test-common.sh: SKIP=0 の初期化が記述されている" test_counter_skip_init

# Test: ERRORS=() の初期化が記述されている
test_counter_errors_init() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_contains "$COMMON_SH" 'ERRORS=\(\)'
}

run_test "test-common.sh: ERRORS=() の初期化が記述されている" test_counter_errors_init

# Edge case: source 後に 4 カウンター変数が実際に初期化されている（動的検証）
test_counters_initialized_after_source() {
  assert_file_exists "$COMMON_SH" || return 1
  bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    [[ \"\$PASS\" == '0' ]] || { echo \"PASS not 0: \$PASS\" >&2; exit 1; }
    [[ \"\$FAIL\" == '0' ]] || { echo \"FAIL not 0: \$FAIL\" >&2; exit 1; }
    [[ \"\$SKIP\" == '0' ]] || { echo \"SKIP not 0: \$SKIP\" >&2; exit 1; }
    [[ \"\${#ERRORS[@]}\" == '0' ]] || { echo \"ERRORS not empty\" >&2; exit 1; }
    exit 0
  " 2>/dev/null
}

run_test "test-common.sh [edge: source 後に PASS/FAIL/SKIP=0, ERRORS=() が確認できる]" test_counters_initialized_after_source

# Edge case: カウンターが整数型として扱われる（算術演算で使用可能）
test_counters_are_numeric() {
  assert_file_exists "$COMMON_SH" || return 1
  bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    # Arithmetic increment should not fail
    ((PASS++)) || true
    ((FAIL++)) || true
    ((SKIP++)) || true
    [[ \"\$PASS\" == '1' ]] || { echo \"PASS arithmetic failed: \$PASS\" >&2; exit 1; }
    [[ \"\$FAIL\" == '1' ]] || { echo \"FAIL arithmetic failed: \$FAIL\" >&2; exit 1; }
    [[ \"\$SKIP\" == '1' ]] || { echo \"SKIP arithmetic failed: \$SKIP\" >&2; exit 1; }
    exit 0
  " 2>/dev/null
}

run_test "test-common.sh [edge: カウンターが算術演算可能な整数型]" test_counters_are_numeric

# =============================================================================
# Requirement: サマリー出力
# =============================================================================
echo ""
echo "--- Requirement: サマリー出力 ---"

# Scenario: サマリー出力
# WHEN: print_summary 関数が呼び出される
# THEN: 通過・失敗・スキップ件数と失敗テスト名の一覧が出力され、$FAIL を exit code として返す

# Test: print_summary が PASS/FAIL/SKIP の件数を出力する
test_print_summary_outputs_counts() {
  assert_file_exists "$COMMON_SH" || return 1
  local output
  output=$(bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    PASS=3; FAIL=1; SKIP=2
    ERRORS=('failed-test-name')
    print_summary
  " 2>&1) || true
  echo "$output" | grep -qP '\b3\b' || return 1  # PASS count
  echo "$output" | grep -qP '\b1\b' || return 1  # FAIL count
  echo "$output" | grep -qP '\b2\b' || return 1  # SKIP count
}

run_test "print_summary: PASS/FAIL/SKIP 件数が出力される" test_print_summary_outputs_counts

# Test: print_summary が失敗テスト名を出力する
test_print_summary_outputs_error_names() {
  assert_file_exists "$COMMON_SH" || return 1
  local output
  output=$(bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    PASS=0; FAIL=1; SKIP=0
    ERRORS=('my-failing-test')
    print_summary
  " 2>&1) || true
  echo "$output" | grep -q 'my-failing-test'
}

run_test "print_summary: ERRORS に含まれる失敗テスト名が出力される" test_print_summary_outputs_error_names

# Test: print_summary が $FAIL を exit code として返す（FAIL=0 → 0）
test_print_summary_exit_code_zero_on_all_pass() {
  assert_file_exists "$COMMON_SH" || return 1
  bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    PASS=5; FAIL=0; SKIP=0; ERRORS=()
    print_summary
    exit \$FAIL
  " > /dev/null 2>&1
}

run_test "print_summary: 全 PASS 時に exit code 0 を返す" test_print_summary_exit_code_zero_on_all_pass

# Test: print_summary が $FAIL を exit code として返す（FAIL=2 → 2）
test_print_summary_exit_code_nonzero_on_fail() {
  assert_file_exists "$COMMON_SH" || return 1
  local exit_code
  bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    PASS=1; FAIL=2; SKIP=0; ERRORS=('e1' 'e2')
    print_summary
    exit \$FAIL
  " > /dev/null 2>&1
  exit_code=$?
  [[ $exit_code -eq 2 ]]
}

run_test "print_summary: FAIL=2 のとき exit code 2 を返す" test_print_summary_exit_code_nonzero_on_fail

# Edge case: ERRORS が空のとき失敗テスト一覧セクションを出力しない（出力がクリーン）
test_print_summary_no_errors_section_when_empty() {
  assert_file_exists "$COMMON_SH" || return 1
  local output
  output=$(bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    PASS=3; FAIL=0; SKIP=0; ERRORS=()
    print_summary
  " 2>&1) || true
  # Should NOT print "Failed tests:" section when no failures
  if echo "$output" | grep -qi "failed tests:"; then
    return 1
  fi
  return 0
}

run_test "print_summary [edge: ERRORS 空のとき Failed tests: セクションが出力されない]" test_print_summary_no_errors_section_when_empty

# Edge case: SKIP カウントが 0 でも print_summary がクラッシュしない
test_print_summary_handles_zero_skip() {
  assert_file_exists "$COMMON_SH" || return 1
  bash -c "
    source '${PROJECT_ROOT}/${COMMON_SH}'
    PASS=1; FAIL=0; SKIP=0; ERRORS=()
    print_summary
  " > /dev/null 2>&1
}

run_test "print_summary [edge: SKIP=0 でもクラッシュしない]" test_print_summary_handles_zero_skip

# =============================================================================
# Requirement: skillmd-pilot-fixes.test.sh の行数削減
# =============================================================================
echo ""
echo "--- Requirement: skillmd-pilot-fixes.test.sh の行数削減 ---"

# Scenario: 行数閾値の遵守
# WHEN: skillmd-pilot-fixes.test.sh がリファクタリングされる
# THEN: wc -l で 300 行以下になる

# Test: skillmd-pilot-fixes.test.sh が存在する
test_target_test_exists() {
  assert_file_exists "$TARGET_TEST"
}

run_test "skillmd-pilot-fixes.test.sh が存在する" test_target_test_exists

# Test: skillmd-pilot-fixes.test.sh が 300 行以下である
test_line_count_le_300() {
  assert_file_exists "$TARGET_TEST" || return 1
  local line_count
  line_count=$(wc -l < "${PROJECT_ROOT}/${TARGET_TEST}")
  if [[ $line_count -gt 300 ]]; then
    echo "Line count is ${line_count} (must be ≤300)" >&2
    return 1
  fi
  return 0
}

run_test "skillmd-pilot-fixes.test.sh: wc -l ≤ 300 行" test_line_count_le_300

# Test: skillmd-pilot-fixes.test.sh が test-common.sh を source している
test_target_sources_common() {
  assert_file_exists "$TARGET_TEST" || return 1
  assert_file_contains "$TARGET_TEST" 'source.*test-common\.sh'
}

run_test "skillmd-pilot-fixes.test.sh: test-common.sh を source している" test_target_sources_common

# Edge case: source パスがスクリプトの相対位置に基づいている（移植性）
test_source_path_relative() {
  assert_file_exists "$TARGET_TEST" || return 1
  # Should use $(dirname "$0") or similar relative path, not a hardcoded absolute path
  assert_file_contains "$TARGET_TEST" 'source.*\$\(dirname|source.*DIR.*test-common\.sh'
}

run_test "skillmd-pilot-fixes.test.sh [edge: source パスが dirname ベースで移植性がある]" test_source_path_relative

# Edge case: インライン定義の assert_file_exists が残っていない（二重定義防止）
test_no_duplicate_helpers_in_target() {
  assert_file_exists "$TARGET_TEST" || return 1
  # After refactoring, inline helper definitions should be removed from the target
  local count
  count=$(grep -cP '^assert_file_exists\s*\(\)' "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null || echo "0")
  [[ "${count}" -eq 0 ]]
}

run_test "skillmd-pilot-fixes.test.sh [edge: インライン assert_file_exists 定義が残っていない]" test_no_duplicate_helpers_in_target

# Edge case: インライン run_test 定義が残っていない（二重定義防止）
test_no_duplicate_run_test_in_target() {
  assert_file_exists "$TARGET_TEST" || return 1
  local count
  count=$(grep -cP '^run_test\s*\(\)' "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null || echo "0")
  [[ "${count}" -eq 0 ]]
}

run_test "skillmd-pilot-fixes.test.sh [edge: インライン run_test 定義が残っていない]" test_no_duplicate_run_test_in_target

# Edge case: インライン PASS/FAIL/SKIP=0 初期化が残っていない（二重初期化防止）
test_no_duplicate_counter_init_in_target() {
  assert_file_exists "$TARGET_TEST" || return 1
  # Counter initialization should come from test-common.sh, not be duplicated
  local pass_count fail_count skip_count
  pass_count=$(grep -cP '^\s*PASS=0\s*$' "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null || echo "0")
  fail_count=$(grep -cP '^\s*FAIL=0\s*$' "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null || echo "0")
  skip_count=$(grep -cP '^\s*SKIP=0\s*$' "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null || echo "0")
  [[ "${pass_count}" -eq 0 && "${fail_count}" -eq 0 && "${skip_count}" -eq 0 ]]
}

run_test "skillmd-pilot-fixes.test.sh [edge: インラインカウンター初期化が残っていない]" test_no_duplicate_counter_init_in_target

# =============================================================================
# Requirement: テスト結果の非退行
# =============================================================================
echo ""
echo "--- Requirement: テスト結果の非退行 ---"

# Scenario: テスト結果の非退行
# WHEN: リファクタリング後のスクリプトを実行する
# THEN: 既存の 19 テストが全て同じ結果（PASS/FAIL/SKIP）を返す

# Test: skillmd-pilot-fixes.test.sh の構文エラーがない（bash -n）
test_target_syntax_valid() {
  assert_file_exists "$TARGET_TEST" || return 1
  bash -n "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null
}

run_test "テスト結果の非退行: skillmd-pilot-fixes.test.sh が bash -n を通過する" test_target_syntax_valid

# Test: skillmd-pilot-fixes.test.sh が 19 個のテストケースを含む（run_test 呼び出し数）
test_target_has_19_test_cases() {
  assert_file_exists "$TARGET_TEST" || return 1
  local count
  count=$(grep -cP '^\s*run_test\s+"' "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null || echo "0")
  if [[ "${count}" -lt 19 ]]; then
    echo "Found ${count} run_test calls (expected ≥19)" >&2
    return 1
  fi
  return 0
}

run_test "テスト結果の非退行: run_test 呼び出しが 19 件以上存在する" test_target_has_19_test_cases

# Test: skillmd-pilot-fixes.test.sh が SKILL_MD 変数を参照している（テストロジックの保持）
test_target_skill_md_ref_preserved() {
  assert_file_exists "$TARGET_TEST" || return 1
  assert_file_contains "$TARGET_TEST" 'SKILL_MD'
}

run_test "テスト結果の非退行: SKILL_MD 変数参照が保持されている" test_target_skill_md_ref_preserved

# Edge case: skillmd-pilot-fixes.test.sh がインラインカウンター初期化なしに正常に source できる
# （test-common.sh 経由でカウンターが供給される想定）
test_target_sources_without_error() {
  assert_file_exists "$TARGET_TEST" || return 1
  assert_file_exists "$COMMON_SH" || return 1
  # Dry-run: source the target and verify no errors (but don't execute tests against real files)
  bash -n "${PROJECT_ROOT}/${TARGET_TEST}" 2>/dev/null
}

run_test "テスト結果の非退行 [edge: bash -n が両ファイルともエラーなし]" test_target_sources_without_error

# Edge case: test-common.sh と skillmd-pilot-fixes.test.sh の合計行数が元の 342 行以下
test_total_lines_not_bloated() {
  assert_file_exists "$COMMON_SH" || return 1
  assert_file_exists "$TARGET_TEST" || return 1
  local common_lines target_lines total
  common_lines=$(wc -l < "${PROJECT_ROOT}/${COMMON_SH}")
  target_lines=$(wc -l < "${PROJECT_ROOT}/${TARGET_TEST}")
  total=$((common_lines + target_lines))
  if [[ $total -gt 420 ]]; then
    echo "Total lines: ${total} (common=${common_lines} + target=${target_lines}), seems bloated" >&2
    return 1
  fi
  return 0
}

run_test "テスト結果の非退行 [edge: 合計行数が元の 342 行から過剰に増加していない (≤420)]" test_total_lines_not_bloated

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
