#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: quick-chain-issue
# Generated from: deltaspec/changes/quick-chain-issue/specs/quick-detection.md
#                  deltaspec/changes/quick-chain-issue/specs/lightweight-chain.md
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

# =============================================================================
# Requirement: 軽量 chain 定義（workflow-setup SKILL.md のドメインルールで実装）
# NOTE: chain-bidir 制約により deps.yaml に独立 chain 定義は不可。
#       workflow-setup SKILL.md のドメインルールとして setup chain の部分実行で対応。
# =============================================================================
echo ""
echo "--- Requirement: 軽量 chain 定義 ---"

# Scenario: workflow-setup SKILL.md が next-step コマンドを使って quick 分岐を機械化している
test_workflow_setup_has_next_step_branch() {
  assert_file_exists "skills/workflow-setup/SKILL.md" || return 1
  assert_file_contains "skills/workflow-setup/SKILL.md" "next-step" || return 1
}
run_test "workflow-setup SKILL.md が next-step コマンドを使って quick 分岐を機械化している" test_workflow_setup_has_next_step_branch


# Scenario: workflow-setup SKILL.md に ac-extract の条件実行の記述がある
test_workflow_setup_skips_ac_extract() {
  assert_file_exists "skills/workflow-setup/SKILL.md" || return 1
  assert_file_contains "skills/workflow-setup/SKILL.md" "NEXT=ac-extract|ac-extract.*の場合のみ" || return 1
}
run_test "workflow-setup SKILL.md に ac-extract の条件実行の記述がある" test_workflow_setup_skips_ac_extract

# Edge case: workflow-setup SKILL.md に setup chain の twl validate が PASS（Violations: 0）
test_twl_validate_pass() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl validate 2>&1)
  if echo "$output" | grep -qP "Violations: [^0]"; then
    echo "$output" | grep "Violations" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "quick-setup chain [edge: twl validate Violations: 0]" test_twl_validate_pass
else
  run_test_skip "quick-setup chain [edge: twl validate Violations: 0]" "twl command not found"
fi

# Edge case: chain-runner.sh に detect_quick_label ヘルパーが存在する
test_init_detect_quick_label_exists() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "detect_quick_label" || return 1
}
run_test "chain-runner.sh [edge: detect_quick_label ヘルパーが存在する]" test_init_detect_quick_label_exists

# Edge case: chain-runner.sh が --argjson is_quick を使用
test_init_uses_argjson() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "\-\-argjson is_quick" || return 1
}
run_test "chain-runner.sh [edge: --argjson is_quick を使用]" test_init_uses_argjson

# =============================================================================
# Requirement: workflow-setup init quick ラベル検出
# =============================================================================
echo ""
echo "--- Requirement: workflow-setup init quick ラベル検出 ---"

# Scenario: chain-runner.sh step_init に quick 検出ロジックがある
test_init_has_quick_detection() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "is_quick|quick" || return 1
}
run_test "chain-runner.sh step_init に quick 検出ロジックがある" test_init_has_quick_detection

# Scenario: chain-runner.sh が gh issue view --json labels を使用
test_init_uses_gh_labels() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" "labels" || return 1
}
run_test "chain-runner.sh が labels を参照する" test_init_uses_gh_labels

# =============================================================================
# Requirement: workflow-setup chain 分岐
# =============================================================================
echo ""
echo "--- Requirement: workflow-setup chain 分岐 ---"

# Scenario: workflow-setup SKILL.md が next-step による機械的 quick 分岐を実装している
test_workflow_setup_quick_branch() {
  assert_file_exists "skills/workflow-setup/SKILL.md" || return 1
  # quick 分岐は chain-runner.sh next-step コマンドに委譲（LLM 自然言語判断を除去）
  assert_file_contains "skills/workflow-setup/SKILL.md" "next-step|QUICK_SKIP" || return 1
}
run_test "workflow-setup SKILL.md に quick 分岐の記述がある" test_workflow_setup_quick_branch

# =============================================================================
# Requirement: co-issue Phase 2 quick 判定基準
# =============================================================================
echo ""
echo "--- Requirement: co-issue Phase 2 quick 判定基準 ---"

# Scenario: co-issue SKILL.md Phase 2 に quick 判定の記述がある
test_co_issue_phase2_quick() {
  assert_file_exists "skills/co-issue/SKILL.md" || return 1
  assert_file_contains "skills/co-issue/SKILL.md" "quick" || return 1
}
run_test "co-issue SKILL.md に quick 判定の記述がある" test_co_issue_phase2_quick

# =============================================================================
# Requirement: co-issue Phase 3b quick 分類妥当性検証
# =============================================================================
echo ""
echo "--- Requirement: co-issue Phase 3b quick 分類妥当性検証 ---"

# Scenario: co-issue SKILL.md に quick-classification カテゴリの記述がある
test_co_issue_phase3b_quick_classification() {
  assert_file_exists "skills/co-issue/SKILL.md" || return 1
  assert_file_contains "skills/co-issue/SKILL.md" "quick-classification" || return 1
}
run_test "co-issue SKILL.md に quick-classification カテゴリの記述がある" test_co_issue_phase3b_quick_classification

# =============================================================================
# Requirement: co-issue Phase 4 quick ラベル付与
# =============================================================================
echo ""
echo "--- Requirement: co-issue Phase 4 quick ラベル付与 ---"

# Scenario: co-issue SKILL.md に --label quick の記述がある
test_co_issue_phase4_label() {
  assert_file_exists "skills/co-issue/SKILL.md" || return 1
  grep -qiP "\-\-label quick|label.*quick" "${PROJECT_ROOT}/skills/co-issue/SKILL.md" || return 1
}
run_test "co-issue SKILL.md に quick ラベル付与の記述がある" test_co_issue_phase4_label

# =============================================================================
# Requirement: twl validate が quick-setup chain でも pass する
# =============================================================================
echo ""
echo "--- Requirement: twl validate ---"

test_twl_validate_quick_setup() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl validate 2>&1)
  if echo "$output" | grep -qP "\[chain-bidir\]|\[chain-type\]|\[step-order\]"; then
    echo "$output" | grep -P "\[chain" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl validate が quick-setup chain でも pass する" test_twl_validate_quick_setup
else
  run_test_skip "twl validate が quick-setup chain でも pass する" "twl command not found"
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
