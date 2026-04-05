#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: pr-cycle chain 分割（pr-verify, pr-fix, pr-merge）
# Issue #10: workflow-pr-cycle を 3 workflow に分割
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

# =============================================================================
# Requirement: pr-verify chain 定義
# =============================================================================
echo ""
echo "--- Requirement: pr-verify chain 定義 ---"

test_pr_verify_chain_exists() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
if 'pr-verify' not in chains:
    sys.exit(1)
sys.exit(0)
"
}
run_test "chains セクションに pr-verify エントリが存在する" test_pr_verify_chain_exists

test_pr_verify_chain_type_b() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr = chains.get('pr-verify', {})
if str(pr.get('type')) != 'B':
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-verify chain の type が B" test_pr_verify_chain_type_b

test_pr_verify_steps() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
steps = chains.get('pr-verify', {}).get('steps', [])
expected = ['ts-preflight', 'phase-review', 'scope-judge', 'pr-test']
if steps != expected:
    print(f'got={steps}, expected={expected}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-verify chain のステップが正しい" test_pr_verify_steps

# =============================================================================
# Requirement: pr-fix chain 定義
# =============================================================================
echo ""
echo "--- Requirement: pr-fix chain 定義 ---"

test_pr_fix_chain_exists() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
if 'pr-fix' not in chains:
    sys.exit(1)
sys.exit(0)
"
}
run_test "chains セクションに pr-fix エントリが存在する" test_pr_fix_chain_exists

test_pr_fix_chain_type_b() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr = chains.get('pr-fix', {})
if str(pr.get('type')) != 'B':
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-fix chain の type が B" test_pr_fix_chain_type_b

test_pr_fix_steps() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
steps = chains.get('pr-fix', {}).get('steps', [])
expected = ['fix-phase', 'post-fix-verify', 'warning-fix']
if steps != expected:
    print(f'got={steps}, expected={expected}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-fix chain のステップが正しい" test_pr_fix_steps

# =============================================================================
# Requirement: pr-merge chain 定義
# =============================================================================
echo ""
echo "--- Requirement: pr-merge chain 定義 ---"

test_pr_merge_chain_exists() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
if 'pr-merge' not in chains:
    sys.exit(1)
sys.exit(0)
"
}
run_test "chains セクションに pr-merge エントリが存在する" test_pr_merge_chain_exists

test_pr_merge_chain_type_b() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr = chains.get('pr-merge', {})
if str(pr.get('type')) != 'B':
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-merge chain の type が B" test_pr_merge_chain_type_b

test_pr_merge_steps() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
steps = chains.get('pr-merge', {}).get('steps', [])
expected = ['e2e-screening', 'pr-cycle-report', 'pr-cycle-analysis', 'all-pass-check', 'merge-gate', 'auto-merge']
if steps != expected:
    print(f'got={steps}, expected={expected}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-merge chain のステップが正しい" test_pr_merge_steps

# =============================================================================
# Requirement: 旧 pr-cycle chain が削除されている
# =============================================================================
echo ""
echo "--- Requirement: 旧 pr-cycle chain 削除 ---"

test_old_pr_cycle_chain_removed() {
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
if 'pr-cycle' in chains:
    print('pr-cycle chain still exists', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "旧 pr-cycle chain が chains セクションから削除されている" test_old_pr_cycle_chain_removed

# =============================================================================
# Requirement: 新 workflow SKILL.md の存在
# =============================================================================
echo ""
echo "--- Requirement: 新 workflow SKILL.md ---"

test_workflow_pr_verify_exists() {
  assert_file_exists "skills/workflow-pr-verify/SKILL.md"
}
run_test "workflow-pr-verify/SKILL.md が存在する" test_workflow_pr_verify_exists

test_workflow_pr_fix_exists() {
  assert_file_exists "skills/workflow-pr-fix/SKILL.md"
}
run_test "workflow-pr-fix/SKILL.md が存在する" test_workflow_pr_fix_exists

test_workflow_pr_merge_exists() {
  assert_file_exists "skills/workflow-pr-merge/SKILL.md"
}
run_test "workflow-pr-merge/SKILL.md が存在する" test_workflow_pr_merge_exists

# =============================================================================
# Requirement: 各 workflow の chain 実行指示
# =============================================================================
echo ""
echo "--- Requirement: chain 実行指示 ---"

test_verify_has_chain_instructions() {
  assert_file_contains "skills/workflow-pr-verify/SKILL.md" 'chain 実行指示（MUST'
}
run_test "workflow-pr-verify に chain 実行指示がある" test_verify_has_chain_instructions

test_fix_has_chain_instructions() {
  assert_file_contains "skills/workflow-pr-fix/SKILL.md" 'chain 実行指示（MUST'
}
run_test "workflow-pr-fix に chain 実行指示がある" test_fix_has_chain_instructions

test_merge_has_chain_instructions() {
  assert_file_contains "skills/workflow-pr-merge/SKILL.md" 'chain 実行指示（MUST'
}
run_test "workflow-pr-merge に chain 実行指示がある" test_merge_has_chain_instructions

# =============================================================================
# Requirement: 各 workflow の compaction 復帰プロトコル
# =============================================================================
echo ""
echo "--- Requirement: compaction 復帰プロトコル ---"

test_verify_has_compaction() {
  assert_file_contains "skills/workflow-pr-verify/SKILL.md" 'compaction 復帰'
}
run_test "workflow-pr-verify に compaction 復帰プロトコルがある" test_verify_has_compaction

test_fix_has_compaction() {
  assert_file_contains "skills/workflow-pr-fix/SKILL.md" 'compaction 復帰'
}
run_test "workflow-pr-fix に compaction 復帰プロトコルがある" test_fix_has_compaction

test_merge_has_compaction() {
  assert_file_contains "skills/workflow-pr-merge/SKILL.md" 'compaction 復帰'
}
run_test "workflow-pr-merge に compaction 復帰プロトコルがある" test_merge_has_compaction

# =============================================================================
# Requirement: ドメインルール配置
# =============================================================================
echo ""
echo "--- Requirement: ドメインルール配置 ---"

test_fix_has_fix_loop_rule() {
  assert_file_contains "skills/workflow-pr-fix/SKILL.md" 'fix.*(loop|ループ|条件)'
}
run_test "workflow-pr-fix に fix ループ条件がある" test_fix_has_fix_loop_rule

test_merge_has_escalation_rule() {
  assert_file_contains "skills/workflow-pr-merge/SKILL.md" '(エスカレーション|retry|Pilot|手動介入)'
}
run_test "workflow-pr-merge にエスカレーション条件がある" test_merge_has_escalation_rule

test_merge_has_merge_failure_rule() {
  assert_file_contains "skills/workflow-pr-merge/SKILL.md" '不変条件 F'
}
run_test "workflow-pr-merge に不変条件 F がある" test_merge_has_merge_failure_rule

# =============================================================================
# Requirement: deps.yaml の workflow エントリ
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml workflow エントリ ---"

test_deps_workflow_pr_verify() {
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
w = skills.get('workflow-pr-verify')
if not w or w.get('type') != 'workflow':
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に workflow-pr-verify が登録されている" test_deps_workflow_pr_verify

test_deps_workflow_pr_fix() {
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
w = skills.get('workflow-pr-fix')
if not w or w.get('type') != 'workflow':
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に workflow-pr-fix が登録されている" test_deps_workflow_pr_fix

test_deps_workflow_pr_merge() {
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
w = skills.get('workflow-pr-merge')
if not w or w.get('type') != 'workflow':
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に workflow-pr-merge が登録されている" test_deps_workflow_pr_merge

test_deps_no_old_workflow_pr_cycle() {
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
if 'workflow-pr-cycle' in skills:
    print('workflow-pr-cycle still in skills', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml から旧 workflow-pr-cycle が削除されている" test_deps_no_old_workflow_pr_cycle

# =============================================================================
# Requirement: コンポーネント step_in 参照更新
# =============================================================================
echo ""
echo "--- Requirement: step_in 参照更新 ---"

test_step_in_references() {
  yaml_get "$DEPS_YAML" "
all_entries = {}
for section in ['commands', 'skills', 'scripts']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

errors = []
# verify components
for comp in ['ts-preflight', 'phase-review', 'scope-judge', 'pr-test']:
    entry = all_entries.get(comp, {})
    step_in = entry.get('step_in', {}) if isinstance(entry, dict) else {}
    if step_in.get('parent') != 'workflow-pr-verify':
        errors.append(f'{comp}: parent={step_in.get(\"parent\")} (expected workflow-pr-verify)')

# fix components
for comp in ['fix-phase', 'post-fix-verify', 'warning-fix']:
    entry = all_entries.get(comp, {})
    step_in = entry.get('step_in', {}) if isinstance(entry, dict) else {}
    if step_in.get('parent') != 'workflow-pr-fix':
        errors.append(f'{comp}: parent={step_in.get(\"parent\")} (expected workflow-pr-fix)')

# merge components
for comp in ['e2e-screening', 'pr-cycle-report', 'pr-cycle-analysis', 'all-pass-check', 'merge-gate', 'auto-merge']:
    entry = all_entries.get(comp, {})
    step_in = entry.get('step_in', {}) if isinstance(entry, dict) else {}
    if step_in.get('parent') != 'workflow-pr-merge':
        errors.append(f'{comp}: parent={step_in.get(\"parent\")} (expected workflow-pr-merge)')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "全コンポーネントの step_in.parent が新 workflow を参照している" test_step_in_references

# =============================================================================
# Requirement: workflow-test-ready 遷移先更新
# =============================================================================
echo ""
echo "--- Requirement: workflow-test-ready 遷移先 ---"

test_test_ready_references_pr_verify() {
  assert_file_contains "skills/workflow-test-ready/SKILL.md" 'workflow-pr-verify'
}
run_test "workflow-test-ready が workflow-pr-verify を参照している" test_test_ready_references_pr_verify

test_test_ready_no_old_reference() {
  assert_file_not_contains "skills/workflow-test-ready/SKILL.md" 'workflow-pr-cycle'
}
run_test "workflow-test-ready に旧 workflow-pr-cycle 参照がない" test_test_ready_no_old_reference

# =============================================================================
# Requirement: twl validate パス
# =============================================================================
echo ""
echo "--- Requirement: twl validate ---"

test_twl_validate_exit_zero() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  cd "${PROJECT_ROOT}" && twl validate &>/dev/null
}

if command -v twl &>/dev/null; then
  run_test "twl validate が exit 0" test_twl_validate_exit_zero
else
  run_test_skip "twl validate が exit 0" "twl command not found"
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
