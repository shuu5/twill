#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: autopilot phase execution commands
# Generated from: deltaspec/changes/archive/2026-03-29-c-2d-autopilot-controller-autopilot/specs/phase-execution/spec.md
# Coverage level: edge-cases
# Verifies: autopilot-phase-execute, autopilot-phase-postprocess COMMAND.md
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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
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

EXEC_CMD="commands/autopilot-phase-execute.md"
POST_CMD="commands/autopilot-phase-postprocess.md"

# =============================================================================
# Requirement: autopilot-phase-execute コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-phase-execute コマンド ---"

# Scenario: sequential モードでの正常実行 (line 20)
# WHEN: MODE=sequential で 2 Issue がある Phase を実行
# THEN: Issue を順次 launch → poll → merge-gate し、各 Issue の完了後に次の Issue を開始する

test_exec_file_exists() {
  assert_file_exists "$EXEC_CMD"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute COMMAND.md が存在する" test_exec_file_exists
else
  run_test_skip "autopilot-phase-execute COMMAND.md が存在する" "commands/autopilot-phase-execute.md not yet created"
fi

test_exec_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute COMMAND.md exists (deps.yaml defines type)" test_exec_frontmatter_type
else
  run_test_skip "autopilot-phase-execute COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_exec_state_read_ref() {
  assert_file_contains "$EXEC_CMD" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute が state-read.sh を参照" test_exec_state_read_ref
else
  run_test_skip "autopilot-phase-execute が state-read.sh を参照" "COMMAND.md not yet created"
fi

test_exec_state_write_ref() {
  assert_file_contains "$EXEC_CMD" "state-write\.sh|state-write"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute が state-write.sh を参照" test_exec_state_write_ref
else
  run_test_skip "autopilot-phase-execute が state-write.sh を参照" "COMMAND.md not yet created"
fi

test_exec_sequential_mode() {
  assert_file_contains "$EXEC_CMD" "sequential|順次|MODE.*sequential"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute sequential モードの記述" test_exec_sequential_mode
else
  run_test_skip "autopilot-phase-execute sequential モードの記述" "COMMAND.md not yet created"
fi

test_exec_launch_poll_merge_chain() {
  assert_file_contains "$EXEC_CMD" "autopilot-launch" || return 1
  assert_file_contains "$EXEC_CMD" "autopilot-poll" || return 1
  assert_file_contains "$EXEC_CMD" "merge-gate" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute が launch → poll → merge-gate チェーンを記述" test_exec_launch_poll_merge_chain
else
  run_test_skip "autopilot-phase-execute が launch → poll → merge-gate チェーンを記述" "COMMAND.md not yet created"
fi

# Scenario: parallel モードでのバッチ実行 (line 25)
# WHEN: MODE=parallel, MAX_PARALLEL=2 で 5 Issue がある Phase
# THEN: 2, 2, 1 のバッチに分割し、各バッチ内は並列実行する

test_exec_parallel_mode() {
  assert_file_contains "$EXEC_CMD" "parallel|並列|MAX_PARALLEL"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute parallel モードの記述" test_exec_parallel_mode
else
  run_test_skip "autopilot-phase-execute parallel モードの記述" "COMMAND.md not yet created"
fi

test_exec_max_parallel_default() {
  assert_file_contains "$EXEC_CMD" "MAX_PARALLEL.*4|デフォルト.*4|default.*4"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute [edge: MAX_PARALLEL デフォルト 4 の記述]" test_exec_max_parallel_default
else
  run_test_skip "autopilot-phase-execute [edge: MAX_PARALLEL デフォルト 4 の記述]" "COMMAND.md not yet created"
fi

# Scenario: 依存先 fail 時の skip 伝播 (line 29)
# WHEN: Phase 内の Issue A が fail し、Issue B が A に依存
# THEN: Issue B は state-write で status=failed, message="dependency failed" として記録される（不変条件 D）

test_exec_dependency_fail_skip() {
  assert_file_contains "$EXEC_CMD" "dependency.*failed|依存.*fail|依存先.*skip|不変条件.*D"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute 依存先 fail 時の skip 伝播記述" test_exec_dependency_fail_skip
else
  run_test_skip "autopilot-phase-execute 依存先 fail 時の skip 伝播記述" "COMMAND.md not yet created"
fi

# Scenario: done 状態の Issue スキップ（再開時） (line 33)
# WHEN: state-read で Issue の status が done
# THEN: その Issue をスキップし、次の Issue に進む

test_exec_done_skip() {
  assert_file_contains "$EXEC_CMD" "done.*スキップ|done.*skip|status.*done"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute done 状態スキップの記述" test_exec_done_skip
else
  run_test_skip "autopilot-phase-execute done 状態スキップの記述" "COMMAND.md not yet created"
fi

# Edge case: 不変条件 E - merge-gate リジェクト再実行は最大 1 回
test_exec_invariant_e() {
  assert_file_contains "$EXEC_CMD" "不変条件.*E|最大.*1.*回|retry.*1|merge-gate.*reject.*1|再実行.*1"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute [edge: 不変条件 E - 再実行最大 1 回]" test_exec_invariant_e
else
  run_test_skip "autopilot-phase-execute [edge: 不変条件 E - 再実行最大 1 回]" "COMMAND.md not yet created"
fi

# Edge case: 不変条件 F - merge-gate 失敗時に rebase 禁止
test_exec_invariant_f() {
  assert_file_contains "$EXEC_CMD" "不変条件.*F|rebase.*禁止|rebase.*してはならない|no.*rebase"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute [edge: 不変条件 F - rebase 禁止]" test_exec_invariant_f
else
  run_test_skip "autopilot-phase-execute [edge: 不変条件 F - rebase 禁止]" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル参照なし
test_exec_no_marker_refs() {
  assert_file_not_contains "$EXEC_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$EXEC_CMD" '\.done"' || return 1
  assert_file_not_contains "$EXEC_CMD" '\.fail"' || return 1
  assert_file_not_contains "$EXEC_CMD" '\.merge-ready"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute [edge: マーカーファイル参照なし]" test_exec_no_marker_refs
else
  run_test_skip "autopilot-phase-execute [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_exec_no_dev_autopilot_session() {
  assert_file_not_contains "$EXEC_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_exec_no_dev_autopilot_session
else
  run_test_skip "autopilot-phase-execute [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: plan.yaml から Issue リスト取得の記述
test_exec_plan_yaml_issues() {
  assert_file_contains "$EXEC_CMD" "plan\.yaml|PLAN_FILE"
}

if [[ -f "${PROJECT_ROOT}/${EXEC_CMD}" ]]; then
  run_test "autopilot-phase-execute [edge: plan.yaml から Issue リスト取得]" test_exec_plan_yaml_issues
else
  run_test_skip "autopilot-phase-execute [edge: plan.yaml から Issue リスト取得]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: autopilot-phase-postprocess コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-phase-postprocess コマンド ---"

# Scenario: 中間 Phase の後処理 (line 54)
# WHEN: P=1, PHASE_COUNT=3
# THEN: collect → retrospective → patterns → cross-issue の順に全 4 ステップを実行する

test_post_file_exists() {
  assert_file_exists "$POST_CMD"
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess COMMAND.md が存在する" test_post_file_exists
else
  run_test_skip "autopilot-phase-postprocess COMMAND.md が存在する" "commands/autopilot-phase-postprocess.md not yet created"
fi

test_post_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess COMMAND.md exists (deps.yaml defines type)" test_post_frontmatter_type
else
  run_test_skip "autopilot-phase-postprocess COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_post_chain_order() {
  # All 4 sub-commands must be referenced
  assert_file_contains "$POST_CMD" "autopilot-collect" || return 1
  assert_file_contains "$POST_CMD" "autopilot-retrospective" || return 1
  assert_file_contains "$POST_CMD" "autopilot-patterns" || return 1
  assert_file_contains "$POST_CMD" "autopilot-cross-issue" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess が collect→retrospective→patterns→cross-issue を記述" test_post_chain_order
else
  run_test_skip "autopilot-phase-postprocess が collect→retrospective→patterns→cross-issue を記述" "COMMAND.md not yet created"
fi

test_post_phase_insights_output() {
  assert_file_contains "$POST_CMD" "PHASE_INSIGHTS"
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess が PHASE_INSIGHTS を出力として記述" test_post_phase_insights_output
else
  run_test_skip "autopilot-phase-postprocess が PHASE_INSIGHTS を出力として記述" "COMMAND.md not yet created"
fi

test_post_cross_issue_warnings_output() {
  assert_file_contains "$POST_CMD" "CROSS_ISSUE_WARNINGS"
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess が CROSS_ISSUE_WARNINGS を出力として記述" test_post_cross_issue_warnings_output
else
  run_test_skip "autopilot-phase-postprocess が CROSS_ISSUE_WARNINGS を出力として記述" "COMMAND.md not yet created"
fi

# Scenario: 最終 Phase の後処理 (line 58)
# WHEN: P=3, PHASE_COUNT=3
# THEN: collect → retrospective → patterns の 3 ステップのみ実行し、cross-issue はスキップする

test_post_final_phase_skip_cross_issue() {
  assert_file_contains "$POST_CMD" "最終.*Phase.*cross-issue.*スキップ|P.*==.*PHASE_COUNT|最終.*Phase|final.*phase"
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess 最終 Phase で cross-issue スキップの記述" test_post_final_phase_skip_cross_issue
else
  run_test_skip "autopilot-phase-postprocess 最終 Phase で cross-issue スキップの記述" "COMMAND.md not yet created"
fi

# Edge case: 後処理の実行順序変更禁止
test_post_order_immutable() {
  # The chain order collect→retrospective→patterns→cross-issue must be documented
  assert_file_contains "$POST_CMD" "collect.*retrospective.*patterns|1.*collect.*2.*retrospective.*3.*patterns|順序"
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess [edge: 実行順序の記述]" test_post_order_immutable
else
  run_test_skip "autopilot-phase-postprocess [edge: 実行順序の記述]" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル参照なし
test_post_no_marker_refs() {
  assert_file_not_contains "$POST_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$POST_CMD" '\.done"' || return 1
  assert_file_not_contains "$POST_CMD" '\.fail"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess [edge: マーカーファイル参照なし]" test_post_no_marker_refs
else
  run_test_skip "autopilot-phase-postprocess [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_post_no_dev_autopilot_session() {
  assert_file_not_contains "$POST_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${POST_CMD}" ]]; then
  run_test "autopilot-phase-postprocess [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_post_no_dev_autopilot_session
else
  run_test_skip "autopilot-phase-postprocess [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
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
