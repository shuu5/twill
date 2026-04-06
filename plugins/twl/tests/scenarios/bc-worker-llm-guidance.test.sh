#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: auto-merge.md + all-pass-check.md
# Generated from: deltaspec/changes/bc-worker-merge-worktree-guard/specs/autopilot-guard.md
# Requirements:
#   - auto-merge autopilot 配下判定 (lines 3-15)
#   - all-pass-check autopilot 配下 merge-ready 宣言 (lines 17-27)
# Coverage level: edge-cases
#
# These are LLM-guidance documents (not directly executable code).
# Tests verify that the correct instruction text is present in each document.
# Manual / LLM-eval verification is required to confirm runtime behavior.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  ! grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"
}

run_test() {
  local name="$1"
  local func="$2"
  local result=0
  "$func" || result=$?
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

AUTO_MERGE_CMD="commands/auto-merge.md"
ALL_PASS_CHECK_CMD="commands/all-pass-check.md"
STATE_WRITE_SCRIPT="scripts/state-write.sh"
STATE_READ_SCRIPT="scripts/state-read.sh"

# =============================================================================
# Requirement: auto-merge autopilot 配下判定
# Source: specs/autopilot-guard.md, line 3
# =============================================================================
echo ""
echo "--- Requirement: auto-merge autopilot 配下判定 ---"

test_auto_merge_exists() {
  assert_file_exists "$AUTO_MERGE_CMD"
}
run_test "auto-merge.md が存在する" test_auto_merge_exists

# ---------------------------------------------------------------------------
# Scenario: autopilot 配下で Worker が pr-cycle を完走 (spec line 7)
# WHEN: issue-{N}.json の status が `running` である
# THEN: auto-merge.md は gh pr merge を実行しない
# THEN: auto-merge.md は worktree 削除を実行しない
# THEN: auto-merge.md は state-write.sh で status を merge-ready に遷移する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: autopilot 配下で Worker が pr-cycle を完走]"

test_auto_merge_checks_running_status() {
  # The document must instruct to check issue-{N}.json status=running
  assert_file_contains "$AUTO_MERGE_CMD" \
    '(running|status.*running|issue.*json|issue-\{N\}\.json)' || return 1
}
run_test "auto-merge.md に status=running チェックの記述がある" test_auto_merge_checks_running_status

test_auto_merge_skips_gh_merge_when_running() {
  # When running, must NOT call gh pr merge — the document should describe
  # skipping / not executing the merge when autopilot guard triggers.
  assert_file_contains "$AUTO_MERGE_CMD" \
    '(merge.*しない|skip.*merge|merge.*skip|merge-ready.*のみ|merge-ready だけ|マージ.*しない|autopilot.*配下|配下.*マージ|merge.*実行しない|実行しない)' || return 1
}
run_test "auto-merge.md に autopilot 配下でマージを実行しない記述がある" test_auto_merge_skips_gh_merge_when_running

test_auto_merge_skips_worktree_delete_when_running() {
  # The document must state that worktree deletion is also skipped
  assert_file_contains "$AUTO_MERGE_CMD" \
    '(worktree.*削除.*しない|削除.*worktree.*しない|worktree.*skip|worktree.*実行しない|worktree.*しない)' || return 1
}
run_test "auto-merge.md に autopilot 配下で worktree 削除をしない記述がある" test_auto_merge_skips_worktree_delete_when_running

test_auto_merge_transitions_to_merge_ready_via_state_write() {
  # Must reference state-write.sh and merge-ready in the same document
  assert_file_contains "$AUTO_MERGE_CMD" '(state-write|state\.write)' || return 1
  assert_file_contains "$AUTO_MERGE_CMD" '(merge.ready|merge-ready)' || return 1
}
run_test "auto-merge.md に state-write.sh 経由での merge-ready 遷移が記述されている" test_auto_merge_transitions_to_merge_ready_via_state_write

# Edge: state-write.sh supports merge-ready status
test_state_write_supports_merge_ready_for_auto_merge() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" '(merge.ready|merge-ready)' || return 1
}
run_test "state-write.sh [edge: merge-ready 状態をサポート]" test_state_write_supports_merge_ready_for_auto_merge

# ---------------------------------------------------------------------------
# Scenario: autopilot 非配下で Worker が pr-cycle を完走 (spec line 13)
# WHEN: issue-{N}.json が存在しない、または status が running でない
# THEN: auto-merge.md は従来通り merge → archive → cleanup を実行する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: autopilot 非配下で Worker が pr-cycle を完走]"

test_auto_merge_runs_full_flow_when_not_running() {
  # Document must describe the standard merge + archive + cleanup flow
  assert_file_contains "$AUTO_MERGE_CMD" \
    '(archive|cleanup|clean.up)' || return 1
  assert_file_contains "$AUTO_MERGE_CMD" \
    '(gh pr merge|squash|マージ)' || return 1
}
run_test "auto-merge.md に非autopilot時の merge→archive→cleanup フローが記述されている" test_auto_merge_runs_full_flow_when_not_running

test_auto_merge_handles_missing_issue_json() {
  # Document must handle the case where issue-{N}.json doesn't exist
  assert_file_contains "$AUTO_MERGE_CMD" \
    '(存在しない|not exist|no.*issue|issue.*json.*ない|if.*not|issue.*exist)' || return 1
}
run_test "auto-merge.md に issue-{N}.json 不在時の動作が記述されている" test_auto_merge_handles_missing_issue_json

# Edge: auto-merge must not attempt auto-rebase on failure (pre-existing rule)
test_auto_merge_no_auto_rebase() {
  assert_file_exists "$AUTO_MERGE_CMD" || return 1
  assert_file_contains "$AUTO_MERGE_CMD" '(rebase.*しない|MUST NOT.*rebase|rebase.*禁止|自動.*rebase|試みない)' || return 1
}
run_test "auto-merge.md [edge: マージ失敗時に自動rebaseしない記述がある]" test_auto_merge_no_auto_rebase

# =============================================================================
# Requirement: all-pass-check autopilot 配下 merge-ready 宣言
# Source: specs/autopilot-guard.md, line 17
# =============================================================================
echo ""
echo "--- Requirement: all-pass-check autopilot 配下 merge-ready 宣言 ---"

test_all_pass_check_exists() {
  assert_file_exists "$ALL_PASS_CHECK_CMD"
}
run_test "all-pass-check.md が存在する" test_all_pass_check_exists

# ---------------------------------------------------------------------------
# Scenario: autopilot 配下で全ステップ PASS (spec line 21)
# WHEN: 全ステップが PASS/WARN で、issue-{N}.json の status が running である
# THEN: all-pass-check.md は state-write.sh で status を merge-ready に遷移する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: autopilot 配下で全ステップ PASS]"

test_all_pass_check_checks_running_status() {
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '(running|status.*running|issue.*json|issue-\{N\}\.json|autopilot.*配下|配下.*autopilot)' || return 1
}
run_test "all-pass-check.md に status=running チェックの記述がある" test_all_pass_check_checks_running_status

test_all_pass_check_transitions_merge_ready_when_pass() {
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(merge.ready|merge-ready)' || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(state-write|state\.write)' || return 1
}
run_test "all-pass-check.md に全PASS時の merge-ready 遷移が記述されている" test_all_pass_check_transitions_merge_ready_when_pass

test_all_pass_check_includes_warn_as_pass() {
  # WARN is treated as PASS per the spec (PASS or WARN, no CRITICAL)
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '(WARN|WARNING|PASS.*または.*WARN|PASS or WARN)' || return 1
}
run_test "all-pass-check.md に WARN を PASS として扱う記述がある" test_all_pass_check_includes_warn_as_pass

# ---------------------------------------------------------------------------
# Scenario: autopilot 配下で FAIL あり (spec line 25)
# WHEN: いずれかのステップが FAIL で、issue-{N}.json の status が running である
# THEN: all-pass-check.md は state-write.sh で status を failed に遷移する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: autopilot 配下で FAIL あり]"

test_all_pass_check_transitions_failed_when_fail() {
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(failed|fail)' || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" '(state-write|state\.write)' || return 1
}
run_test "all-pass-check.md に FAIL 時の failed 遷移が記述されている" test_all_pass_check_transitions_failed_when_fail

test_all_pass_check_records_failure_step() {
  # Must describe recording which step failed and why
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '(失敗.*ステップ|failure.*step|reason|理由|記録|record|details)' || return 1
}
run_test "all-pass-check.md に失敗ステップの記録が記述されている" test_all_pass_check_records_failure_step

# Edge: state-write.sh supports failed status
test_state_write_supports_failed_for_all_pass() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" '(failed)' || return 1
}
run_test "state-write.sh [edge: failed 状態をサポート]" test_state_write_supports_failed_for_all_pass

# Edge: no legacy flags/markers remain
test_all_pass_check_no_auto_merge_flag() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_not_contains "$ALL_PASS_CHECK_CMD" '\-\-auto-merge' || return 1
}
run_test "all-pass-check.md [edge: --auto-merge フラグがない]" test_all_pass_check_no_auto_merge_flag

test_all_pass_check_no_dev_autopilot_session() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_not_contains "$ALL_PASS_CHECK_CMD" 'DEV_AUTOPILOT_SESSION' || return 1
}
run_test "all-pass-check.md [edge: DEV_AUTOPILOT_SESSION がない]" test_all_pass_check_no_dev_autopilot_session

# =============================================================================
# Manual verification note
# =============================================================================
echo ""
echo "  NOTE: auto-merge.md and all-pass-check.md are LLM guidance documents."
echo "  Runtime behavior (LLM following the instructions) requires manual / LLM-eval"
echo "  verification and cannot be validated by automated document inspection alone."

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
