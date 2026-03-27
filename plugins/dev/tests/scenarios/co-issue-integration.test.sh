#!/usr/bin/env bash
# =============================================================================
# Document/Structure Verification Tests: co-issue-integration.md
# Generated from: openspec/changes/b-7-self-improve-review-hook/specs/co-issue-integration.md
# Coverage level: edge-cases
#
# Note: co-issue integration is a markdown-based AI skill (SKILL.md).
# These tests verify structural correctness: required sections in SKILL.md,
# explore-summary.md detection logic, and phase skip flow documentation.
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
# Requirement: co-issue の explore-summary 検出
# =============================================================================
echo ""
echo "--- Requirement: co-issue の explore-summary 検出 ---"

CO_ISSUE_SKILL="skills/co-issue/SKILL.md"

# Scenario: explore-summary.md が存在する場合 (line 8)
# WHEN: co-issue が起動され .controller-issue/explore-summary.md が存在する
# THEN: 「前回の探索結果が残っています。継続しますか？」とユーザーに確認する
test_coissue_explore_summary_detection() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  assert_file_contains_all "$CO_ISSUE_SKILL" \
    "explore-summary\.md|explore.summary" \
    "存在|detect|check|確認"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "explore-summary.md 存在時の検出 [SKILL.md 記載検証]" test_coissue_explore_summary_detection
else
  run_test_skip "explore-summary.md 存在時の検出" "co-issue SKILL.md not found"
fi

# Edge case: 検出パスが .controller-issue/explore-summary.md で正確
test_coissue_explore_summary_path() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  assert_file_contains "$CO_ISSUE_SKILL" "\.controller-issue/explore-summary\.md"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "explore-summary 検出 [edge: パスが正確]" test_coissue_explore_summary_path
else
  run_test_skip "explore-summary 検出 [edge: パスが正確]" "co-issue SKILL.md not found"
fi

# Edge case: ユーザーへの確認メッセージが記載されている
test_coissue_user_confirmation_message() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  assert_file_contains "$CO_ISSUE_SKILL" "継続.*ますか|前回.*探索|続行.*確認|resume.*previous"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "explore-summary 検出 [edge: 確認メッセージ記載]" test_coissue_user_confirmation_message
else
  run_test_skip "explore-summary 検出 [edge: 確認メッセージ記載]" "co-issue SKILL.md not found"
fi

# Scenario: 継続を選択した場合 (line 12)
# WHEN: ユーザーが継続を選択する
# THEN: co-issue は Phase 1（探索）をスキップし Phase 2（分解判断）から続行する
test_coissue_continue_phase_skip() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  assert_file_contains_all "$CO_ISSUE_SKILL" \
    "Phase\s*1.*スキップ|Phase.*1.*skip|探索.*スキップ" \
    "Phase\s*2|分解判断|decompos"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "継続を選択した場合の Phase スキップ [SKILL.md 記載検証]" test_coissue_continue_phase_skip
else
  run_test_skip "継続を選択した場合の Phase スキップ" "co-issue SKILL.md not found"
fi

# Edge case: Phase 1 と Phase 2 の両方が明確に定義されている
test_coissue_phases_defined() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  assert_file_contains "$CO_ISSUE_SKILL" "Phase\s*1|フェーズ\s*1" || return 1
  assert_file_contains "$CO_ISSUE_SKILL" "Phase\s*2|フェーズ\s*2"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "Phase スキップ [edge: Phase 1/2 が両方定義]" test_coissue_phases_defined
else
  run_test_skip "Phase スキップ [edge: Phase 1/2 が両方定義]" "co-issue SKILL.md not found"
fi

# Scenario: 継続を拒否した場合 (line 16)
# WHEN: ユーザーが継続を拒否する
# THEN: explore-summary.md を削除し、通常の Phase 1 から開始する
test_coissue_reject_continue() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  assert_file_contains_all "$CO_ISSUE_SKILL" \
    "拒否|reject|いいえ|no.*場合|断" \
    "削除|delete|remove|クリア"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "継続を拒否した場合 [SKILL.md 記載検証]" test_coissue_reject_continue
else
  run_test_skip "継続を拒否した場合" "co-issue SKILL.md not found"
fi

# Edge case: 拒否時に explore-summary.md が削除されることが明記
test_coissue_reject_deletes_file() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  # Should mention deleting/removing the explore-summary file on rejection
  assert_file_contains "$CO_ISSUE_SKILL" "explore-summary.*削除|削除.*explore-summary|remove.*explore|delete.*explore"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "継続拒否 [edge: explore-summary.md 削除が明記]" test_coissue_reject_deletes_file
else
  run_test_skip "継続拒否 [edge: explore-summary.md 削除が明記]" "co-issue SKILL.md not found"
fi

# Scenario: explore-summary.md が存在しない場合 (line 20)
# WHEN: co-issue が起動され .controller-issue/explore-summary.md が存在しない
# THEN: 通常の Phase 1（探索）から開始する（既存動作に影響なし）
test_coissue_no_explore_summary() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  # The SKILL.md should document that without explore-summary, normal flow continues
  # This is typically implicit, but should be documented for clarity
  assert_file_contains "$CO_ISSUE_SKILL" "存在しない|not.*exist|通常|normal|デフォルト|default"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "explore-summary.md が存在しない場合 [SKILL.md 記載検証]" test_coissue_no_explore_summary
else
  run_test_skip "explore-summary.md が存在しない場合" "co-issue SKILL.md not found"
fi

# Edge case: 既存の co-issue フローに影響がないことが明記
test_coissue_no_regression() {
  assert_file_exists "$CO_ISSUE_SKILL" || return 1
  assert_file_contains "$CO_ISSUE_SKILL" "既存.*影響|影響.*ない|backward.*compat|互換"
}

if assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "explore-summary 不在 [edge: 既存動作への非影響明記]" test_coissue_no_regression
else
  run_test_skip "explore-summary 不在 [edge: 既存動作への非影響明記]" "co-issue SKILL.md not found"
fi

# =============================================================================
# Cross-cutting edge cases
# =============================================================================
echo ""
echo "--- Cross-cutting: self-improve-review ↔ co-issue 連携 ---"

# Edge case: COMMAND.md と SKILL.md で .controller-issue/explore-summary.md パスが一致
test_cross_path_consistency() {
  local command_file="commands/self-improve-review/COMMAND.md"
  if ! assert_file_exists "$command_file" 2>/dev/null; then
    return 1
  fi
  if ! assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
    return 1
  fi
  # Both files should reference the same path
  assert_file_contains "$command_file" "\.controller-issue/explore-summary\.md" || return 1
  assert_file_contains "$CO_ISSUE_SKILL" "\.controller-issue/explore-summary\.md"
}

if assert_file_exists "commands/self-improve-review/COMMAND.md" 2>/dev/null && assert_file_exists "$CO_ISSUE_SKILL" 2>/dev/null; then
  run_test "COMMAND.md と SKILL.md のパス一致 [cross-cutting]" test_cross_path_consistency
else
  run_test_skip "COMMAND.md と SKILL.md のパス一致" "one or both files not yet created"
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
