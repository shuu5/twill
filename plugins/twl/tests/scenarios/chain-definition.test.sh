#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: chain-definition.md
# Generated from: deltaspec/changes/b-4-workflow-setup-chain-driven/specs/chain-definition.md
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

# =============================================================================
# Requirement: setup chain 定義
# =============================================================================
echo ""
echo "--- Requirement: setup chain 定義 ---"

# Scenario: chains セクションが存在する (line 7)
# WHEN: deps.yaml を確認する
# THEN: chains: セクションに setup: エントリが存在し、type: "A" と description が設定されている
test_chains_section_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
if 'setup' not in chains:
    sys.exit(1)
sys.exit(0)
"
}
run_test "chains セクションに setup エントリが存在する" test_chains_section_exists

test_chains_setup_type_a() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
setup = chains.get('setup', {})
if str(setup.get('type')) != 'A':
    sys.exit(1)
sys.exit(0)
"
}
run_test "setup chain の type が A" test_chains_setup_type_a

test_chains_setup_description() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
setup = chains.get('setup', {})
if not setup.get('description'):
    sys.exit(1)
sys.exit(0)
"
}
run_test "setup chain に description が設定されている" test_chains_setup_description

# Edge case: type の値が文字列 "A" である（数値や小文字ではない）
test_chains_setup_type_exact_string() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
setup = chains.get('setup', {})
t = setup.get('type')
if not isinstance(t, str) or t != 'A':
    sys.exit(1)
sys.exit(0)
"
}
run_test "setup chain [edge: type が文字列 'A' (大文字)]" test_chains_setup_type_exact_string

# Edge case: description が空文字でない
test_chains_setup_description_nonempty() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
setup = chains.get('setup', {})
desc = setup.get('description', '')
if not desc or not desc.strip():
    sys.exit(1)
sys.exit(0)
"
}
run_test "setup chain [edge: description が空文字でない]" test_chains_setup_description_nonempty

# Scenario: steps が正しい順序で定義されている (line 11)
# WHEN: setup chain の steps を確認する
# THEN: init -> worktree-create -> project-board-status-update -> crg-auto-build -> change-propose -> ac-extract -> workflow-test-ready の順序で列挙されている
EXPECTED_STEPS='["init", "worktree-create", "project-board-status-update", "crg-auto-build", "change-propose", "ac-extract"]'

test_chains_steps_order() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
chains = data.get('chains', {})
setup = chains.get('setup', {})
steps_raw = setup.get('steps', [])
# steps can be a list of strings or a list of dicts with 'name'/'component' key
step_names = []
for s in steps_raw:
    if isinstance(s, str):
        step_names.append(s)
    elif isinstance(s, dict):
        name = s.get('name') or s.get('component') or s.get('step') or ''
        step_names.append(name)
expected = json.loads('${EXPECTED_STEPS}')
if step_names != expected:
    print(f'Expected: {expected}', file=sys.stderr)
    print(f'Got:      {step_names}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "steps が正しい順序で定義されている" test_chains_steps_order

# Edge case: steps の数が正確に 7 個
test_chains_steps_count() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
setup = chains.get('setup', {})
steps = setup.get('steps', [])
if len(steps) != 6:
    print(f'Expected 6 steps, got {len(steps)}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "steps [edge: 数が正確に 6 個]" test_chains_steps_count

# Edge case: steps に重複がない
test_chains_steps_no_duplicates() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
setup = chains.get('setup', {})
steps_raw = setup.get('steps', [])
step_names = []
for s in steps_raw:
    if isinstance(s, str):
        step_names.append(s)
    elif isinstance(s, dict):
        name = s.get('name') or s.get('component') or s.get('step') or ''
        step_names.append(name)
if len(step_names) != len(set(step_names)):
    sys.exit(1)
sys.exit(0)
"
}
run_test "steps [edge: 重複がない]" test_chains_steps_no_duplicates

# Edge case: steps の最初が init で最後が workflow-test-ready
test_chains_steps_first_last() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
setup = chains.get('setup', {})
steps_raw = setup.get('steps', [])
step_names = []
for s in steps_raw:
    if isinstance(s, str):
        step_names.append(s)
    elif isinstance(s, dict):
        name = s.get('name') or s.get('component') or s.get('step') or ''
        step_names.append(name)
if not step_names:
    sys.exit(1)
if step_names[0] != 'init' or step_names[-1] != 'ac-extract':
    sys.exit(1)
sys.exit(0)
"
}
run_test "steps [edge: 最初が init / 最後が ac-extract]" test_chains_steps_first_last

# Scenario: twl chain validate が pass する (line 15)
# WHEN: twl chain validate を実行する
# THEN: setup chain に関する CRITICAL エラーが 0 件である
test_twl_chain_validate() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  # twl chain validate は wrapper 未対応のため twl validate で chain 検証
  output=$(cd "${PROJECT_ROOT}" && twl validate 2>&1)
  # Check no chain-bidir or chain-type errors related to setup chain
  if echo "$output" | grep -qP "\[chain-bidir\]|\[chain-type\]|\[step-order\]"; then
    echo "$output" | grep -P "\[chain" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl chain validate が pass する" test_twl_chain_validate
else
  run_test_skip "twl chain validate が pass する" "twl command not found"
fi

# Edge case: twl chain validate 出力に setup 関連の WARNING もない
test_twl_chain_validate_no_warnings() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl validate 2>&1)
  if echo "$output" | grep -qP "\[chain.*WARNING\].*setup|setup.*\[chain.*WARNING\]"; then
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl chain validate [edge: setup 関連 WARNING なし]" test_twl_chain_validate_no_warnings
else
  run_test_skip "twl chain validate [edge: setup 関連 WARNING なし]" "twl command not found"
fi

# =============================================================================
# Requirement: chain 参加コンポーネントの双方向参照
# =============================================================================
echo ""
echo "--- Requirement: chain 参加コンポーネントの双方向参照 ---"

# Scenario: コンポーネント側の chain フィールド (line 23)
# WHEN: init, worktree-create, project-board-status-update, crg-auto-build, change-propose, ac-extract, workflow-test-ready の deps.yaml エントリを確認する
# THEN: 全コンポーネントに chain: "setup" が設定されている
CHAIN_COMPONENTS='["init", "worktree-create", "project-board-status-update", "crg-auto-build", "change-propose", "ac-extract"]'

test_components_chain_field() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${CHAIN_COMPONENTS}')
# Search across all sections (commands first, then skills, then scripts)
# Use first-found to avoid scripts overwriting commands with same name
all_entries = {}
for section in ['scripts', 'skills', 'commands']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

missing = []
for comp in components:
    entry = all_entries.get(comp)
    if entry is None:
        missing.append(f'{comp}: not found in deps.yaml')
        continue
    if not isinstance(entry, dict):
        missing.append(f'{comp}: not a dict')
        continue
    chain_val = entry.get('chain')
    if str(chain_val) != 'setup':
        missing.append(f'{comp}: chain={chain_val} (expected setup)')

if missing:
    for m in missing:
        print(m, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "全 chain 参加コンポーネントに chain: setup が設定されている" test_components_chain_field

# Edge case: chain フィールドの値が文字列 "setup" である（大文字混在や別値でない）
test_components_chain_field_exact() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${CHAIN_COMPONENTS}')
all_entries = {}
for section in ['scripts', 'skills', 'commands']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

for comp in components:
    entry = all_entries.get(comp, {})
    if not isinstance(entry, dict):
        sys.exit(1)
    chain_val = entry.get('chain')
    if not isinstance(chain_val, str) or chain_val != 'setup':
        sys.exit(1)
sys.exit(0)
"
}
run_test "chain フィールド [edge: 値が文字列 'setup']" test_components_chain_field_exact

# Scenario: step_in の双方向整合性 (line 28)
# WHEN: workflow-setup の calls と各コンポーネントの step_in を確認する
# THEN: calls[i].step と対応コンポーネントの step_in.step が一致する
test_step_in_bidirectional() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json

# Collect all entries (commands last to take priority over scripts with same name)
all_entries = {}
for section in ['scripts', 'skills', 'commands']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

# Get workflow-setup calls
ws = all_entries.get('workflow-setup', {})
if not isinstance(ws, dict):
    print('workflow-setup not found', file=sys.stderr)
    sys.exit(1)

calls = ws.get('calls', [])
if not calls:
    print('workflow-setup has no calls', file=sys.stderr)
    sys.exit(1)

errors = []
for call in calls:
    if not isinstance(call, dict):
        continue
    call_step = call.get('step')
    call_component = call.get('component') or call.get('name') or call.get('atomic') or call.get('workflow')
    if not call_component or call_step is None:
        continue
    # Find the component and check step_in
    comp_entry = all_entries.get(call_component, {})
    if not isinstance(comp_entry, dict):
        errors.append(f'{call_component}: not found')
        continue
    step_in = comp_entry.get('step_in', {})
    if isinstance(step_in, dict):
        comp_step = step_in.get('step')
    else:
        comp_step = step_in
    if str(comp_step) != str(call_step):
        errors.append(f'{call_component}: calls.step={call_step} != step_in.step={comp_step}')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "step_in の双方向整合性" test_step_in_bidirectional

# Edge case: 全 calls エントリに step と component フィールドが存在する
test_calls_have_required_fields() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
all_entries = {}
for section in ['scripts', 'skills', 'commands']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

ws = all_entries.get('workflow-setup', {})
calls = ws.get('calls', [])
if not calls:
    sys.exit(1)

for i, call in enumerate(calls):
    if not isinstance(call, dict):
        print(f'calls[{i}] is not a dict', file=sys.stderr)
        sys.exit(1)
    if 'step' not in call:
        print(f'calls[{i}] missing step field', file=sys.stderr)
        sys.exit(1)
    if 'component' not in call and 'name' not in call and 'atomic' not in call and 'workflow' not in call:
        print(f'calls[{i}] missing component/name/atomic/workflow field', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "step_in [edge: calls に step と component フィールド存在]" test_calls_have_required_fields

# Edge case: 各コンポーネントの step_in に chain フィールドも含む
test_step_in_has_chain() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${CHAIN_COMPONENTS}')
all_entries = {}
for section in ['scripts', 'skills', 'commands']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

for comp in components:
    entry = all_entries.get(comp, {})
    if not isinstance(entry, dict):
        sys.exit(1)
    step_in = entry.get('step_in', {})
    if not isinstance(step_in, dict) or not step_in.get('parent'):
        print(f'{comp}: step_in missing parent', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "step_in [edge: step_in に parent フィールドが含まれる]" test_step_in_has_chain

# Scenario: twl check での双方向検証 (line 31)
# WHEN: twl check を実行する
# THEN: [chain-bidir] および [step-bidir] エラーが 0 件である
test_twl_check_bidir() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl check 2>&1)
  local exit_code=$?
  if echo "$output" | grep -qP "\[chain-bidir\].*error|\[step-bidir\].*error"; then
    echo "$output" | grep -P "\[chain-bidir\]|\[step-bidir\]" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl check で [chain-bidir] [step-bidir] エラーが 0 件" test_twl_check_bidir
else
  run_test_skip "twl check で [chain-bidir] [step-bidir] エラーが 0 件" "twl command not found"
fi

# Edge case: twl check 全体が exit 0
test_twl_check_exit_zero() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl check 2>&1)
  local exit_code=$?
  [[ $exit_code -eq 0 ]]
}

if command -v twl &>/dev/null; then
  run_test "twl check [edge: exit code が 0]" test_twl_check_exit_zero
else
  run_test_skip "twl check [edge: exit code が 0]" "twl command not found"
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
