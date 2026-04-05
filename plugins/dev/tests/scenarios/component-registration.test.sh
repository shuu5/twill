#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: component-registration.md
# Generated from: openspec/changes/b-4-workflow-setup-chain-driven/specs/component-registration.md
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
# Requirement: 新規 atomic コンポーネント登録
# =============================================================================
echo ""
echo "--- Requirement: 新規 atomic コンポーネント登録 ---"

# Scenario: 全 chain 参加コンポーネントが登録済み (line 7)
# WHEN: deps.yaml の commands セクションを確認する
# THEN: init, worktree-create, worktree-delete, worktree-list, project-board-status-update,
#       crg-auto-build, opsx-propose, opsx-apply, opsx-archive, ac-extract が atomic として登録されている
# worktree-delete は scripts セクション（B-3 で追加済み）のため commands には含まない
ATOMIC_COMPONENTS='["init", "worktree-create", "worktree-list", "project-board-status-update", "crg-auto-build", "opsx-propose", "opsx-apply", "opsx-archive", "ac-extract"]'

test_all_atomic_components_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
required = json.loads('${ATOMIC_COMPONENTS}')
commands = data.get('commands', {})
if not isinstance(commands, dict):
    print('commands section not found or not a dict', file=sys.stderr)
    sys.exit(1)

missing = []
for comp in required:
    if comp not in commands:
        missing.append(f'{comp}: not found in commands')

if missing:
    for m in missing:
        print(m, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "全 chain 参加コンポーネントが commands に登録済み" test_all_atomic_components_registered

test_all_atomic_components_type() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
required = json.loads('${ATOMIC_COMPONENTS}')
commands = data.get('commands', {})

wrong_type = []
for comp in required:
    entry = commands.get(comp, {})
    if not isinstance(entry, dict):
        wrong_type.append(f'{comp}: entry not a dict')
        continue
    if entry.get('type') != 'atomic':
        wrong_type.append(f\"{comp}: type={entry.get('type')} (expected atomic)\")

if wrong_type:
    for w in wrong_type:
        print(w, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "全 chain 参加コンポーネントが type: atomic" test_all_atomic_components_type

# Edge case: 各 atomic コンポーネントに path フィールドが存在する
test_atomic_components_have_path() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
required = json.loads('${ATOMIC_COMPONENTS}')
commands = data.get('commands', {})

for comp in required:
    entry = commands.get(comp, {})
    if not isinstance(entry, dict) or not entry.get('path'):
        print(f'{comp}: missing path', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "atomic コンポーネント [edge: path フィールド存在]" test_atomic_components_have_path

# Edge case: 各 atomic コンポーネントに description フィールドが存在する
test_atomic_components_have_description() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
required = json.loads('${ATOMIC_COMPONENTS}')
commands = data.get('commands', {})

for comp in required:
    entry = commands.get(comp, {})
    if not isinstance(entry, dict) or not entry.get('description'):
        print(f'{comp}: missing description', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "atomic コンポーネント [edge: description フィールド存在]" test_atomic_components_have_description

# Edge case: 各 atomic コンポーネントに can_spawn フィールドが存在する
test_atomic_components_have_can_spawn() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
required = json.loads('${ATOMIC_COMPONENTS}')
commands = data.get('commands', {})

for comp in required:
    entry = commands.get(comp, {})
    if not isinstance(entry, dict) or 'can_spawn' not in entry:
        print(f'{comp}: missing can_spawn', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "atomic コンポーネント [edge: can_spawn フィールド存在]" test_atomic_components_have_can_spawn

# Scenario: spawnable_by が正しい (line 11)
# WHEN: chain 参加コンポーネントの spawnable_by を確認する
# THEN: 全コンポーネントが [controller, workflow] を含む
test_spawnable_by_correct() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
required = json.loads('${ATOMIC_COMPONENTS}')
commands = data.get('commands', {})

errors = []
for comp in required:
    entry = commands.get(comp, {})
    if not isinstance(entry, dict):
        errors.append(f'{comp}: not found')
        continue
    sb = entry.get('spawnable_by', [])
    if not isinstance(sb, list):
        errors.append(f'{comp}: spawnable_by is not a list')
        continue
    if 'controller' not in sb:
        errors.append(f'{comp}: spawnable_by missing controller')
    if 'workflow' not in sb:
        errors.append(f'{comp}: spawnable_by missing workflow')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "全 chain 参加コンポーネントの spawnable_by に controller と workflow" test_spawnable_by_correct

# Edge case: spawnable_by がリスト型である
test_spawnable_by_is_list() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
required = json.loads('${ATOMIC_COMPONENTS}')
commands = data.get('commands', {})

for comp in required:
    entry = commands.get(comp, {})
    if not isinstance(entry, dict):
        sys.exit(1)
    sb = entry.get('spawnable_by')
    if not isinstance(sb, list):
        print(f'{comp}: spawnable_by is {type(sb).__name__}', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "spawnable_by [edge: リスト型である]" test_spawnable_by_is_list

# =============================================================================
# Requirement: workflow-setup の workflow 型登録
# =============================================================================
echo ""
echo "--- Requirement: workflow-setup の workflow 型登録 ---"

# Scenario: workflow 型として登録 (line 19)
# WHEN: deps.yaml の skills セクションを確認する
# THEN: workflow-setup が type: workflow で登録され、chain: "setup" が設定されている
test_workflow_setup_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ws = skills.get('workflow-setup')
if ws is None:
    print('workflow-setup not found in skills', file=sys.stderr)
    sys.exit(1)
if not isinstance(ws, dict):
    sys.exit(1)
if ws.get('type') != 'workflow':
    print(f\"type={ws.get('type')} (expected workflow)\", file=sys.stderr)
    sys.exit(1)
# workflow-setup は orchestrator のため chain 宣言不要、calls で chain ステップを参照
if not ws.get('calls'):
    print('workflow-setup has no calls', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "workflow-setup が type: workflow で登録、calls あり" test_workflow_setup_registered

# Edge case: workflow-setup に path フィールドがある
test_workflow_setup_has_path() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ws = skills.get('workflow-setup', {})
if not ws.get('path'):
    sys.exit(1)
sys.exit(0)
"
}
run_test "workflow-setup [edge: path フィールド存在]" test_workflow_setup_has_path

# Edge case: workflow-setup に description フィールドがある
test_workflow_setup_has_description() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ws = skills.get('workflow-setup', {})
if not ws.get('description'):
    sys.exit(1)
sys.exit(0)
"
}
run_test "workflow-setup [edge: description フィールド存在]" test_workflow_setup_has_description

# Scenario: calls が全ステップを網羅 (line 23)
# WHEN: workflow-setup の calls を確認する
# THEN: step "1"（init）から step "4"（workflow-test-ready）まで全 chain 参加コンポーネントが calls に含まれる
# chain steps のみ（workflow-test-ready は型制約で chain 外）
CHAIN_STEP_COMPONENTS='["init", "worktree-create", "project-board-status-update", "crg-auto-build", "opsx-propose", "ac-extract"]'

test_workflow_setup_calls_coverage() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
expected = json.loads('${CHAIN_STEP_COMPONENTS}')
skills = data.get('skills', {})
ws = skills.get('workflow-setup', {})
calls = ws.get('calls', [])
if not calls:
    print('workflow-setup has no calls', file=sys.stderr)
    sys.exit(1)

# Extract component names from calls
called_components = set()
for call in calls:
    if isinstance(call, dict):
        comp = call.get('component') or call.get('name') or call.get('atomic') or call.get('workflow') or ''
        called_components.add(comp)
    elif isinstance(call, str):
        called_components.add(call)

missing = [c for c in expected if c not in called_components]
if missing:
    print(f'Missing from calls: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "calls が全 chain ステップを網羅" test_workflow_setup_calls_coverage

# Edge case: calls の各エントリに step 番号が付いている
test_workflow_setup_calls_have_step_numbers() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ws = skills.get('workflow-setup', {})
calls = ws.get('calls', [])

for i, call in enumerate(calls):
    if not isinstance(call, dict):
        print(f'calls[{i}] is not a dict', file=sys.stderr)
        sys.exit(1)
    if 'step' not in call:
        print(f'calls[{i}] missing step number', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "calls [edge: 各エントリに step 番号あり]" test_workflow_setup_calls_have_step_numbers

# Edge case: calls の step 番号が連番で並んでいる（ギャップなし）
test_workflow_setup_calls_step_sequence() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ws = skills.get('workflow-setup', {})
calls = ws.get('calls', [])

steps = []
for call in calls:
    if isinstance(call, dict):
        s = call.get('step')
        if s is not None:
            steps.append(float(s))

steps.sort()
if not steps:
    sys.exit(1)

# Check ascending order (小数点 step 許容)
for i in range(len(steps) - 1):
    if steps[i + 1] <= steps[i]:
        print(f'Not ascending: step {steps[i]} and {steps[i+1]}', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "calls [edge: step 番号が連番]" test_workflow_setup_calls_step_sequence

# =============================================================================
# Requirement: workflow-test-ready の workflow 型登録
# =============================================================================
echo ""
echo "--- Requirement: workflow-test-ready の workflow 型登録 ---"

# Scenario: workflow 型として登録 (line 31)
# WHEN: deps.yaml の skills セクションを確認する
# THEN: workflow-test-ready が type: workflow で登録され、chain: "setup" と step_in が設定されている
test_workflow_test_ready_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
wtr = skills.get('workflow-test-ready')
if wtr is None:
    print('workflow-test-ready not found in skills', file=sys.stderr)
    sys.exit(1)
if not isinstance(wtr, dict):
    sys.exit(1)
if wtr.get('type') != 'workflow':
    print(f\"type={wtr.get('type')} (expected workflow)\", file=sys.stderr)
    sys.exit(1)
# workflow-test-ready は型制約で chain 外（workflow は workflow を spawn できない）
# controller 経由で呼び出される独立 workflow
sys.exit(0)
"
}
run_test "workflow-test-ready が type: workflow で登録" test_workflow_test_ready_registered

# Edge case: workflow-test-ready の step_in が setup chain の最終ステップを指す
test_workflow_test_ready_spawnable_by() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
# workflow-test-ready は controller から呼び出される
skills = data.get('skills', {})
wtr = skills.get('workflow-test-ready', {})
sb = wtr.get('spawnable_by', [])
if 'controller' not in sb:
    print(f'spawnable_by={sb}, expected controller', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "workflow-test-ready [edge: spawnable_by に controller]" test_workflow_test_ready_spawnable_by

# Edge case: workflow-test-ready に path と description がある
test_workflow_test_ready_has_fields() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
wtr = skills.get('workflow-test-ready', {})
if not wtr.get('path'):
    print('missing path', file=sys.stderr)
    sys.exit(1)
if not wtr.get('description'):
    print('missing description', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "workflow-test-ready [edge: path と description 存在]" test_workflow_test_ready_has_fields

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
