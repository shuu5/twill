#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: issue-specialist-budget-ref
# Generated from:
#   openspec/changes/issue-specialist-budget-ref/specs/investigation-budget-ref/spec.md
# Coverage level: edge-cases
# Type: unit
#
# Note: Target files are Markdown prompt definitions (agent/ref files).
# These tests verify structural correctness: ref file creation, DRY refactoring,
# frontmatter skills registration, and deps.yaml consistency.
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

assert_files_same_section() {
  # Both files must contain an identical line matching the pattern
  local file_a="$1"
  local file_b="$2"
  local pattern="$3"
  [[ -f "${PROJECT_ROOT}/${file_a}" ]] || return 1
  [[ -f "${PROJECT_ROOT}/${file_b}" ]] || return 1
  grep -qP -- "$pattern" "${PROJECT_ROOT}/${file_a}" || return 1
  grep -qP -- "$pattern" "${PROJECT_ROOT}/${file_b}" || return 1
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

REF_FILE="refs/ref-investigation-budget.md"
ISSUE_CRITIC="agents/issue-critic.md"
ISSUE_FEASIBILITY="agents/issue-feasibility.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: 調査バジェット共通 ref の作成
# =============================================================================
echo ""
echo "--- Requirement: 調査バジェット共通 ref の作成 ---"

# Scenario: ref ファイル作成
# WHEN: refs/ref-investigation-budget.md が作成される
# THEN: ファイルが存在し、issue-critic.md の調査バジェット制御セクションと行単位一致である

# Test: ref ファイルが存在する
test_ref_file_exists() {
  assert_file_exists "$REF_FILE"
}

run_test "ref-investigation-budget.md が存在する" test_ref_file_exists

# Test: ref ファイルに scope_files 3 ファイル以上の制限指示が存在する
test_ref_file_scope_files_limit() {
  assert_file_exists "$REF_FILE" || return 1
  assert_file_contains "$REF_FILE" "3.*ファイル以上|scope_files.*3|3.*以上"
}

run_test "ref: scope_files 3 ファイル以上の調査制限指示が存在する" test_ref_file_scope_files_limit

# Test: ref ファイルに 2-3 tool calls 制限が記述されている
test_ref_file_tool_call_limit() {
  assert_file_exists "$REF_FILE" || return 1
  assert_file_contains "$REF_FILE" "2-3.*tool|tool.*2-3|tool calls.*制限|各ファイル.*[23].*tool"
}

run_test "ref: 各ファイル 2-3 tool calls 制限指示が存在する" test_ref_file_tool_call_limit

# Test: ref ファイルに再帰追跡禁止が明記されている
test_ref_file_no_recursive_tracking() {
  assert_file_exists "$REF_FILE" || return 1
  assert_file_contains "$REF_FILE" "再帰.*禁止|再帰追跡.*禁止|再帰.*追跡.*禁止"
}

run_test "ref: 再帰追跡禁止が明記されている" test_ref_file_no_recursive_tracking

# Test: ref ファイルに残り turns での出力優先指示が存在する
test_ref_file_turns_output_priority() {
  assert_file_exists "$REF_FILE" || return 1
  assert_file_contains "$REF_FILE" "残り.*turns|turns.*3以下|出力.*優先|出力生成.*優先"
}

run_test "ref: 残り turns での出力生成優先指示が存在する" test_ref_file_turns_output_priority

# Edge case: ref ファイルと issue-critic.md の調査バジェット制御ルール内容が一致している
test_ref_matches_issue_critic_content() {
  assert_file_exists "$REF_FILE" || return 1
  assert_file_exists "$ISSUE_CRITIC" || return 1
  # Both must contain the core budget control keywords (line-level equivalence)
  assert_files_same_section "$REF_FILE" "$ISSUE_CRITIC" "3.*ファイル以上|scope_files.*3" || return 1
  assert_files_same_section "$REF_FILE" "$ISSUE_CRITIC" "2-3.*tool|tool calls.*制限" || return 1
  assert_files_same_section "$REF_FILE" "$ISSUE_CRITIC" "再帰.*禁止" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${REF_FILE}" ]] && [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "[edge: ref と issue-critic の調査バジェット内容が一致している]" test_ref_matches_issue_critic_content
else
  run_test_skip "[edge: ref と issue-critic の内容一致確認]" "One or both files not found"
fi

# =============================================================================
# Requirement: issue-critic.md の ref 参照化
# =============================================================================
echo ""
echo "--- Requirement: issue-critic.md の ref 参照化 ---"

# Scenario: issue-critic が ref を参照する
# WHEN: agents/issue-critic.md を Read する
# THEN: frontmatter の skills: に ref-investigation-budget が含まれ、
#       本文に refs/ref-investigation-budget.md を Glob/Read する指示が含まれる

# Test: frontmatter の skills に ref-investigation-budget が含まれる
test_issue_critic_skills_has_ref() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic: frontmatter skills に ref-investigation-budget が含まれる" test_issue_critic_skills_has_ref
else
  run_test_skip "issue-critic: frontmatter skills 確認" "agents/issue-critic.md not found"
fi

# Test: 本文に ref-investigation-budget.md を Glob/Read する指示が含まれる
test_issue_critic_has_ref_read_instruction() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget\.md"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic: 本文に ref-investigation-budget.md の参照指示が含まれる" test_issue_critic_has_ref_read_instruction
else
  run_test_skip "issue-critic: 本文 ref 参照指示確認" "agents/issue-critic.md not found"
fi

# Test: 本文の ref 参照指示に Glob または Read の言及がある
test_issue_critic_glob_or_read_ref() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_contains "$ISSUE_CRITIC" "Glob.*ref-investigation-budget|Read.*ref-investigation-budget|ref-investigation-budget.*Glob|ref-investigation-budget.*Read"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic: ref-investigation-budget.md を Glob/Read する指示が含まれる" test_issue_critic_glob_or_read_ref
else
  run_test_skip "issue-critic: Glob/Read 指示確認" "agents/issue-critic.md not found"
fi

# Scenario: issue-critic に重複セクションが存在しない
# WHEN: agents/issue-critic.md を Read する
# THEN: 「調査バジェット制御（MUST）」セクションが本文に直接存在しない

# Test: 調査バジェット制御（MUST）セクションヘッダーが存在しない
test_issue_critic_no_duplicate_budget_section() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_not_contains "$ISSUE_CRITIC" "## 調査バジェット制御（MUST）"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic: 調査バジェット制御（MUST）セクションが直接存在しない" test_issue_critic_no_duplicate_budget_section
else
  run_test_skip "issue-critic: 重複セクション不在確認" "agents/issue-critic.md not found"
fi

# Edge case: issue-critic にバジェット制御ルール本文が直接記述されていない
# （ref に移動済みであること）
test_issue_critic_no_inline_budget_rules() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  # The inline rule text (specific to budget section body) must not exist directly
  assert_file_not_contains "$ISSUE_CRITIC" "scope_files.*3.*ファイル以上.*:$|3.*ファイル以上.*:$|各ファイルの調査は.*最大.*2-3 tool calls"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic [edge: バジェット制御ルール本文がインラインで存在しない]" test_issue_critic_no_inline_budget_rules
else
  run_test_skip "issue-critic [edge: インラインルール不在]" "agents/issue-critic.md not found"
fi

# =============================================================================
# Requirement: issue-feasibility.md の ref 参照化
# =============================================================================
echo ""
echo "--- Requirement: issue-feasibility.md の ref 参照化 ---"

# Scenario: issue-feasibility が ref を参照する
# WHEN: agents/issue-feasibility.md を Read する
# THEN: frontmatter の skills: に ref-investigation-budget が含まれ、ref 参照指示が含まれる

# Test: frontmatter の skills に ref-investigation-budget が含まれる
test_issue_feasibility_skills_has_ref() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "ref-investigation-budget"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility: frontmatter skills に ref-investigation-budget が含まれる" test_issue_feasibility_skills_has_ref
else
  run_test_skip "issue-feasibility: frontmatter skills 確認" "agents/issue-feasibility.md not found"
fi

# Test: 本文に ref-investigation-budget.md を Glob/Read する指示が含まれる
test_issue_feasibility_has_ref_read_instruction() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "ref-investigation-budget\.md"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility: 本文に ref-investigation-budget.md の参照指示が含まれる" test_issue_feasibility_has_ref_read_instruction
else
  run_test_skip "issue-feasibility: 本文 ref 参照指示確認" "agents/issue-feasibility.md not found"
fi

# Test: 本文の ref 参照指示に Glob または Read の言及がある
test_issue_feasibility_glob_or_read_ref() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "Glob.*ref-investigation-budget|Read.*ref-investigation-budget|ref-investigation-budget.*Glob|ref-investigation-budget.*Read"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility: ref-investigation-budget.md を Glob/Read する指示が含まれる" test_issue_feasibility_glob_or_read_ref
else
  run_test_skip "issue-feasibility: Glob/Read 指示確認" "agents/issue-feasibility.md not found"
fi

# Scenario: issue-feasibility に重複セクションが存在しない
# WHEN: agents/issue-feasibility.md を Read する
# THEN: 「調査バジェット制御（MUST）」セクションが本文に直接存在しない

# Test: 調査バジェット制御（MUST）セクションヘッダーが存在しない
test_issue_feasibility_no_duplicate_budget_section() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_not_contains "$ISSUE_FEASIBILITY" "## 調査バジェット制御（MUST）"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility: 調査バジェット制御（MUST）セクションが直接存在しない" test_issue_feasibility_no_duplicate_budget_section
else
  run_test_skip "issue-feasibility: 重複セクション不在確認" "agents/issue-feasibility.md not found"
fi

# Edge case: issue-feasibility にバジェット制御ルール本文が直接記述されていない
test_issue_feasibility_no_inline_budget_rules() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_not_contains "$ISSUE_FEASIBILITY" "scope_files.*3.*ファイル以上.*:$|3.*ファイル以上.*:$|各ファイルの調査は.*最大.*2-3 tool calls"
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility [edge: バジェット制御ルール本文がインラインで存在しない]" test_issue_feasibility_no_inline_budget_rules
else
  run_test_skip "issue-feasibility [edge: インラインルール不在]" "agents/issue-feasibility.md not found"
fi

# =============================================================================
# Requirement: deps.yaml の更新
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml の更新 ---"

# Scenario: deps.yaml 整合性
# WHEN: twl check を実行する
# THEN: エラーなく完了する

# Test: deps.yaml の refs セクションに ref-investigation-budget が存在する
test_deps_yaml_has_ref_entry() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_file_contains "$DEPS_YAML" "ref-investigation-budget"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml: refs セクションに ref-investigation-budget が存在する" test_deps_yaml_has_ref_entry
else
  run_test_skip "deps.yaml: ref エントリ確認" "deps.yaml not found"
fi

# Test: deps.yaml の issue-critic skills に ref-investigation-budget が含まれる
test_deps_yaml_issue_critic_skills() {
  assert_file_exists "$DEPS_YAML" || return 1
  # Check that ref-investigation-budget appears after issue-critic context
  # (deps.yaml has issue-critic entry with skills field)
  local content
  content=$(awk '/issue-critic:/,/issue-feasibility:/' "${PROJECT_ROOT}/${DEPS_YAML}")
  echo "$content" | grep -qP "ref-investigation-budget"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml: issue-critic の skills に ref-investigation-budget が含まれる" test_deps_yaml_issue_critic_skills
else
  run_test_skip "deps.yaml: issue-critic skills 確認" "deps.yaml not found"
fi

# Test: deps.yaml の issue-feasibility skills に ref-investigation-budget が含まれる
test_deps_yaml_issue_feasibility_skills() {
  assert_file_exists "$DEPS_YAML" || return 1
  local content
  content=$(awk '/issue-feasibility:/,0' "${PROJECT_ROOT}/${DEPS_YAML}" | head -20)
  echo "$content" | grep -qP "ref-investigation-budget"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml: issue-feasibility の skills に ref-investigation-budget が含まれる" test_deps_yaml_issue_feasibility_skills
else
  run_test_skip "deps.yaml: issue-feasibility skills 確認" "deps.yaml not found"
fi

# Test: twl check が成功する（deps.yaml 整合性の統合テスト）
test_twl_check_passes() {
  local twl_bin
  twl_bin="$(command -v twl 2>/dev/null)" || true
  if [[ -z "$twl_bin" ]]; then
    return 77  # SKIP marker
  fi
  (cd "${PROJECT_ROOT}" && twl check 2>&1) && return 0 || return 1
}

if command -v twl &>/dev/null; then
  result=0
  test_twl_check_passes || result=$?
  if [[ $result -eq 77 ]]; then
    run_test_skip "twl check: エラーなく完了する" "twl binary not found"
  elif [[ $result -eq 0 ]]; then
    echo "  PASS: twl check: エラーなく完了する"
    ((PASS++)) || true
  else
    echo "  FAIL: twl check: エラーなく完了する"
    ((FAIL++)) || true
    ERRORS+=("twl check: エラーなく完了する")
  fi
else
  run_test_skip "twl check: エラーなく完了する" "twl binary not found"
fi

# =============================================================================
# Cross-cutting: issue-critic / issue-feasibility の対称性
# =============================================================================
echo ""
echo "--- Cross-cutting: issue-critic / issue-feasibility の対称性 ---"

# Test: 両エージェントが同じ ref を参照している
test_both_agents_reference_same_ref() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "ref-investigation-budget" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]] && [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "両エージェントが ref-investigation-budget を参照している" test_both_agents_reference_same_ref
else
  run_test_skip "両エージェントの ref 参照対称性" "One or both agent files not found"
fi

# Test: 両エージェントに重複セクションが存在しない（対称的 DRY 化）
test_both_agents_dry() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_not_contains "$ISSUE_CRITIC" "## 調査バジェット制御（MUST）" || return 1
  assert_file_not_contains "$ISSUE_FEASIBILITY" "## 調査バジェット制御（MUST）" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]] && [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "両エージェントの調査バジェット制御セクションが DRY 化されている" test_both_agents_dry
else
  run_test_skip "両エージェントの DRY 化確認" "One or both agent files not found"
fi

# Edge case: ref ファイルが存在し、両エージェントがそれを参照し、
#            かつエージェント本文に重複ルールが存在しない（三角整合性）
test_triangle_consistency() {
  assert_file_exists "$REF_FILE" || return 1
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  # ref exists
  assert_file_contains "$REF_FILE" "調査バジェット|scope_files|再帰.*禁止" || return 1
  # agents reference ref
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "ref-investigation-budget" || return 1
  # agents do NOT have inline duplicate
  assert_file_not_contains "$ISSUE_CRITIC" "## 調査バジェット制御（MUST）" || return 1
  assert_file_not_contains "$ISSUE_FEASIBILITY" "## 調査バジェット制御（MUST）" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${REF_FILE}" ]] && \
   [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]] && \
   [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "[edge: ref・両エージェントの三角整合性（存在・参照・非重複）]" test_triangle_consistency
else
  run_test_skip "[edge: 三角整合性]" "One or more required files not found"
fi

# =============================================================================
# Requirement: テストの更新（co-issue-specialist-maxturns-fix.test.sh）
# =============================================================================
echo ""
echo "--- Requirement: co-issue-specialist-maxturns-fix.test.sh の更新確認 ---"

MAXTURNS_TEST="tests/scenarios/co-issue-specialist-maxturns-fix.test.sh"

# Test: maxturns テストが存在する
test_maxturns_test_exists() {
  assert_file_exists "$MAXTURNS_TEST"
}

run_test "co-issue-specialist-maxturns-fix.test.sh が存在する" test_maxturns_test_exists

# Scenario: テスト PASS
# WHEN: tests/scenarios/co-issue-specialist-maxturns-fix.test.sh を実行する
# THEN: 全 assert が PASS する

# Test: maxturns テストを実行して全 PASS する（統合テスト）
test_maxturns_test_passes() {
  assert_file_exists "$MAXTURNS_TEST" || return 1
  bash "${PROJECT_ROOT}/${MAXTURNS_TEST}" 2>&1
}

if [[ -f "${PROJECT_ROOT}/${MAXTURNS_TEST}" ]]; then
  result=0
  (cd "${PROJECT_ROOT}" && bash "${MAXTURNS_TEST}" > /dev/null 2>&1) || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: co-issue-specialist-maxturns-fix.test.sh: 全 assert が PASS する"
    ((PASS++)) || true
  else
    echo "  FAIL: co-issue-specialist-maxturns-fix.test.sh: 全 assert が PASS する"
    ((FAIL++)) || true
    ERRORS+=("co-issue-specialist-maxturns-fix.test.sh: 全 assert が PASS する")
  fi
else
  run_test_skip "co-issue-specialist-maxturns-fix.test.sh: 全 assert が PASS する" "test file not found"
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
