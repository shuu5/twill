#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: pr-cycle-chain.md
# Generated from: openspec/changes/b-5-pr-cycle-merge-gate-chain-driven/specs/pr-cycle-chain.md
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
# Requirement: pr-cycle chain 定義
# =============================================================================
echo ""
echo "--- Requirement: pr-cycle chain 定義 ---"

# Scenario: chain 定義の完全性 (line 7)
# WHEN: deps.yaml に pr-cycle chain が定義される
# THEN: chains セクションに type: "A" と steps リストが含まれる
# AND: 全ステップのコンポーネントが deps.yaml の commands/skills セクションに存在する
test_pr_cycle_chain_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
if 'pr-cycle' not in chains:
    print('pr-cycle chain not found in chains', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "chains セクションに pr-cycle エントリが存在する" test_pr_cycle_chain_exists

test_pr_cycle_chain_type_a() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr_cycle = chains.get('pr-cycle', {})
if str(pr_cycle.get('type')) != 'A':
    print(f'type={pr_cycle.get(\"type\")} (expected A)', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-cycle chain の type が A" test_pr_cycle_chain_type_a

test_pr_cycle_chain_has_steps() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr_cycle = chains.get('pr-cycle', {})
steps = pr_cycle.get('steps', [])
if not steps or len(steps) == 0:
    print('pr-cycle chain has no steps', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-cycle chain に steps リストが存在する" test_pr_cycle_chain_has_steps

test_pr_cycle_all_steps_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr_cycle = chains.get('pr-cycle', {})
steps_raw = pr_cycle.get('steps', [])

step_names = []
for s in steps_raw:
    if isinstance(s, str):
        step_names.append(s)
    elif isinstance(s, dict):
        name = s.get('name') or s.get('component') or s.get('step') or ''
        step_names.append(name)

all_entries = {}
for section in ['commands', 'skills', 'scripts']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

missing = [n for n in step_names if n not in all_entries]
if missing:
    print(f'Missing components: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "全ステップのコンポーネントが deps.yaml に登録されている" test_pr_cycle_all_steps_registered

# Edge case: type が文字列 "A" (数値や小文字でない)
test_pr_cycle_type_exact_string() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr_cycle = chains.get('pr-cycle', {})
t = pr_cycle.get('type')
if not isinstance(t, str) or t != 'A':
    print(f'type is {type(t).__name__}={t} (expected str A)', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-cycle chain [edge: type が文字列 'A']" test_pr_cycle_type_exact_string

# Edge case: description が設定されている
test_pr_cycle_has_description() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr_cycle = chains.get('pr-cycle', {})
desc = pr_cycle.get('description', '')
if not desc or not desc.strip():
    sys.exit(1)
sys.exit(0)
"
}
run_test "pr-cycle chain [edge: description が設定されている]" test_pr_cycle_has_description

# Edge case: steps に重複がない
test_pr_cycle_steps_no_duplicates() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
chains = data.get('chains', {})
pr_cycle = chains.get('pr-cycle', {})
steps_raw = pr_cycle.get('steps', [])
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
run_test "pr-cycle chain [edge: steps に重複がない]" test_pr_cycle_steps_no_duplicates

# Scenario: chain validate パス (line 12)
# WHEN: loom chain validate を実行する
# THEN: pr-cycle chain の双方向参照整合性が検証され pass する
# AND: 各コンポーネントの chain/step_in フィールドが chain 定義と一致する
test_pr_cycle_chain_validate() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom validate 2>&1)
  # Check no chain errors related to pr-cycle chain
  if echo "$output" | grep -qP "\[chain-bidir\]|\[chain-type\]|\[step-order\]"; then
    echo "$output" | grep -P "\[chain" >&2
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom chain validate が pass する (pr-cycle)" test_pr_cycle_chain_validate
else
  run_test_skip "loom chain validate が pass する (pr-cycle)" "loom command not found"
fi

# Edge case: loom validate が exit 0
test_loom_validate_exit_zero() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  cd "${PROJECT_ROOT}" && loom validate &>/dev/null
}

if command -v loom &>/dev/null; then
  run_test "loom validate [edge: exit code が 0]" test_loom_validate_exit_zero
else
  run_test_skip "loom validate [edge: exit code が 0]" "loom command not found"
fi

# Scenario: chain ステップと SKILL.md の責務分離 (line 17)
# WHEN: workflow-pr-cycle SKILL.md が chain-driven に縮小される
# THEN: SKILL.md にはステップ順序やルーティングロジックが含まれない
# AND: ドメインルール（fix ループ条件、merge-gate 判定基準、エスカレーション条件）のみが残る
SKILL_PR_CYCLE="skills/workflow-pr-cycle/SKILL.md"

test_skill_no_step_routing() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  # Should NOT contain step routing like "Step 1:", "Step 2:", etc.
  assert_file_not_contains "$SKILL_PR_CYCLE" 'Step\s+\d+\s*:' || return 1
  return 0
}
run_test "SKILL.md にステップ番号ルーティングが含まれない" test_skill_no_step_routing

test_skill_has_fix_loop_rule() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  # Should contain fix loop domain rule
  assert_file_contains "$SKILL_PR_CYCLE" 'fix.*(loop|ループ|条件|phase)' || return 1
  return 0
}
run_test "SKILL.md に fix ループ条件が記述されている" test_skill_has_fix_loop_rule

test_skill_has_merge_gate_criteria() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  # Should contain merge-gate judgment criteria
  assert_file_contains "$SKILL_PR_CYCLE" '(CRITICAL|merge.gate|severity|confidence)' || return 1
  return 0
}
run_test "SKILL.md に merge-gate 判定基準が記述されている" test_skill_has_merge_gate_criteria

test_skill_has_escalation_rule() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  # Should contain escalation condition
  assert_file_contains "$SKILL_PR_CYCLE" '(エスカレーション|escalat|retry|Pilot|手動)' || return 1
  return 0
}
run_test "SKILL.md にエスカレーション条件が記述されている" test_skill_has_escalation_rule

# Edge case: SKILL.md に "verify → review → test" 等のフロー列挙がない
test_skill_no_flow_enumeration() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  assert_file_not_contains "$SKILL_PR_CYCLE" 'verify\s*→\s*review\s*→\s*test' || return 1
  return 0
}
run_test "SKILL.md [edge: フロー列挙 verify→review→test がない]" test_skill_no_flow_enumeration

# =============================================================================
# Requirement: pr-cycle chain コンポーネント登録
# =============================================================================
echo ""
echo "--- Requirement: pr-cycle chain コンポーネント登録 ---"

# Scenario: 新規 atomic コンポーネント登録 (line 27)
# WHEN: ts-preflight, scope-judge, pr-test, post-fix-verify, warning-fix,
#       pr-cycle-report, all-pass-check, ac-verify を deps.yaml に追加する
# THEN: 各コンポーネントに type: atomic, chain: "pr-cycle", step_in が設定される
# AND: COMMAND.md ファイルが commands/ 配下に存在する
ATOMIC_COMPONENTS='["ts-preflight", "scope-judge", "pr-test", "post-fix-verify", "warning-fix", "pr-cycle-report", "all-pass-check", "ac-verify"]'

test_atomic_components_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${ATOMIC_COMPONENTS}')
all_entries = {}
for section in ['commands', 'skills', 'scripts']:
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
    if entry.get('type') != 'atomic':
        missing.append(f'{comp}: type={entry.get(\"type\")} (expected atomic)')
    if str(entry.get('chain')) != 'pr-cycle':
        missing.append(f'{comp}: chain={entry.get(\"chain\")} (expected pr-cycle)')
    step_in = entry.get('step_in')
    if not step_in or not isinstance(step_in, dict):
        missing.append(f'{comp}: step_in missing or not a dict')

if missing:
    for m in missing:
        print(m, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "新規 atomic コンポーネントが全て deps.yaml に登録されている" test_atomic_components_registered

test_atomic_command_files_exist() {
  local components=("ts-preflight" "scope-judge" "pr-test" "post-fix-verify" "warning-fix" "pr-cycle-report" "all-pass-check" "ac-verify")
  local missing=()
  for comp in "${components[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/commands/${comp}/COMMAND.md" ]]; then
      missing+=("commands/${comp}/COMMAND.md")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    for m in "${missing[@]}"; do
      echo "  missing: $m" >&2
    done
    return 1
  fi
  return 0
}
run_test "新規 atomic コンポーネントの COMMAND.md が存在する" test_atomic_command_files_exist

# Edge case: step_in に parent フィールドがある
test_atomic_step_in_has_parent() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${ATOMIC_COMPONENTS}')
all_entries = {}
for section in ['commands', 'skills', 'scripts']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

errors = []
for comp in components:
    entry = all_entries.get(comp, {})
    if not isinstance(entry, dict):
        errors.append(f'{comp}: not a dict')
        continue
    step_in = entry.get('step_in', {})
    if not isinstance(step_in, dict) or not step_in.get('parent'):
        errors.append(f'{comp}: step_in missing parent')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "atomic コンポーネント [edge: step_in に parent がある]" test_atomic_step_in_has_parent

# Edge case: step_in.step が非空文字列
test_atomic_step_in_step_nonempty() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${ATOMIC_COMPONENTS}')
all_entries = {}
for section in ['commands', 'skills', 'scripts']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

for comp in components:
    entry = all_entries.get(comp, {})
    if not isinstance(entry, dict):
        sys.exit(1)
    step_in = entry.get('step_in', {})
    if not isinstance(step_in, dict):
        sys.exit(1)
    step = step_in.get('step')
    if not step or not str(step).strip():
        print(f'{comp}: step_in.step is empty', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "atomic コンポーネント [edge: step_in.step が非空]" test_atomic_step_in_step_nonempty

# Scenario: 新規 composite コンポーネント登録 (line 31)
# WHEN: merge-gate, phase-review, fix-phase, e2e-screening を deps.yaml に追加する
# THEN: 各コンポーネントに type: composite, chain: "pr-cycle", step_in, calls が設定される
# AND: SKILL.md ファイルが skills/ 配下に存在する
COMPOSITE_COMPONENTS='["merge-gate", "phase-review", "fix-phase", "e2e-screening"]'

test_composite_components_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${COMPOSITE_COMPONENTS}')
all_entries = {}
for section in ['commands', 'skills', 'scripts']:
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
    if entry.get('type') != 'composite':
        missing.append(f'{comp}: type={entry.get(\"type\")} (expected composite)')
    if str(entry.get('chain')) != 'pr-cycle':
        missing.append(f'{comp}: chain={entry.get(\"chain\")} (expected pr-cycle)')
    step_in = entry.get('step_in')
    if not step_in or not isinstance(step_in, dict):
        missing.append(f'{comp}: step_in missing or not a dict')
    calls = entry.get('calls')
    if not calls or not isinstance(calls, list) or len(calls) == 0:
        missing.append(f'{comp}: calls missing or empty')

if missing:
    for m in missing:
        print(m, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "新規 composite コンポーネントが全て deps.yaml に登録されている" test_composite_components_registered

test_composite_skill_files_exist() {
  local components=("merge-gate" "phase-review" "fix-phase" "e2e-screening")
  local missing=()
  for comp in "${components[@]}"; do
    if [[ ! -f "${PROJECT_ROOT}/skills/${comp}/SKILL.md" ]]; then
      missing+=("skills/${comp}/SKILL.md")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    for m in "${missing[@]}"; do
      echo "  missing: $m" >&2
    done
    return 1
  fi
  return 0
}
run_test "新規 composite コンポーネントの SKILL.md が存在する" test_composite_skill_files_exist

# Edge case: composite の calls が全て deps.yaml に存在するコンポーネントを参照している
test_composite_calls_targets_exist() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
components = json.loads('${COMPOSITE_COMPONENTS}')
all_entries = {}
for section in ['commands', 'skills', 'scripts']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

errors = []
for comp in components:
    entry = all_entries.get(comp, {})
    if not isinstance(entry, dict):
        continue
    calls = entry.get('calls', [])
    for call in calls:
        if isinstance(call, dict):
            target = call.get('component') or call.get('atomic') or call.get('specialist') or call.get('name') or ''
        elif isinstance(call, str):
            target = call
        else:
            continue
        if target and target not in all_entries:
            errors.append(f'{comp}: calls target \"{target}\" not in deps.yaml')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "composite [edge: calls の参照先が全て deps.yaml に存在する]" test_composite_calls_targets_exist

# =============================================================================
# Requirement: workflow-pr-cycle SKILL.md 縮小
# =============================================================================
echo ""
echo "--- Requirement: workflow-pr-cycle SKILL.md 縮小 ---"

# Scenario: ドメインルールのみ残留 (line 43)
# WHEN: workflow-pr-cycle SKILL.md を更新する
# THEN: fix ループの条件が記述されている
# AND: merge-gate 判定基準（CRITICAL && confidence >= 80）が記述されている
# AND: エスカレーション条件（retry_count >= 1 で Pilot 報告）が記述されている
# AND: ステップ番号のルーティングは含まれない
test_skill_fix_loop_domain_rule() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  assert_file_contains "$SKILL_PR_CYCLE" '(fix|テスト失敗|再テスト|fix.phase)' || return 1
  return 0
}
run_test "SKILL.md にfix ループドメインルールが記述されている" test_skill_fix_loop_domain_rule

test_skill_merge_gate_threshold() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  # Should contain the threshold: CRITICAL + confidence >= 80
  assert_file_contains "$SKILL_PR_CYCLE" '(CRITICAL|confidence|80)' || return 1
  return 0
}
run_test "SKILL.md にmerge-gate 閾値 (CRITICAL/confidence/80) が記述されている" test_skill_merge_gate_threshold

test_skill_escalation_retry() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  # Should mention retry / escalation / Pilot report
  assert_file_contains "$SKILL_PR_CYCLE" '(retry|リトライ|エスカレーション|Pilot|手動介入)' || return 1
  return 0
}
run_test "SKILL.md にエスカレーション条件 (retry/Pilot) が記述されている" test_skill_escalation_retry

test_skill_no_step_numbers() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  # Must not have step routing like "Step 1:", "Step 2: review"
  assert_file_not_contains "$SKILL_PR_CYCLE" 'Step\s+\d+\s*:\s*(verify|review|test|fix|visual|report|merge)' || return 1
  return 0
}
run_test "SKILL.md [edge: Step N: <ステップ名> ルーティングが不在]" test_skill_no_step_numbers

# Edge case: SKILL.md 内の行数が過度に長くない (chain-driven で縮小されたことの簡易検証)
test_skill_reasonable_size() {
  assert_file_exists "$SKILL_PR_CYCLE" || return 1
  local lines
  lines=$(wc -l < "${PROJECT_ROOT}/${SKILL_PR_CYCLE}")
  # 縮小後は 200 行以下が目安 (元は数百行のフロー記述があった想定)
  if [[ $lines -gt 300 ]]; then
    echo "SKILL.md is ${lines} lines (expected <= 300 for chain-driven reduction)" >&2
    return 1
  fi
  return 0
}
run_test "SKILL.md [edge: 行数が 300 以下 (chain-driven 縮小)]" test_skill_reasonable_size

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
