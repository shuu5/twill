#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-self-improve spawn 受取・deps.yaml 更新
# Generated from: deltaspec/changes/issue-440/specs/co-self-improve-spawn/spec.md
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

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

yaml_list_contains() {
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
  ((SKIP++)) || true
}

CO_SELF_IMPROVE_SKILL="skills/co-self-improve/SKILL.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: co-self-improve の spawn 受取手順
# Scenario: su-observer からの spawn 受信 (spec.md line 7)
# WHEN: su-observer が cld-spawn を使って co-self-improve を起動する
# THEN: co-self-improve は spawn 時プロンプトから「対象 session 情報」
#       「タスク内容」「観察モード」を解釈し、適切な内部フローに進まなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: co-self-improve の spawn 受取手順 ---"

# Test: co-self-improve SKILL.md の冒頭に spawn 受取手順が記載されている
test_spawn_procedure_at_head() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  # 冒頭 30 行以内に spawn 受取に関する記述があるか
  python3 - "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    lines = f.readlines()

head = ''.join(lines[:30])
# spawn / 受取 / 受信 のいずれかが冒頭 30 行に含まれているか
if not re.search(r'spawn|受取|受信|起動.*受', head, re.IGNORECASE):
    print("spawn procedure not found in first 30 lines", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "co-self-improve SKILL.md 冒頭に spawn 受取手順が記載されている" test_spawn_procedure_at_head
else
  run_test_skip "spawn 受取手順 冒頭記載" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# Test: spawn 時プロンプトから「対象 session 情報」を受け取る記述がある
test_spawn_receives_session_info() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  assert_file_contains "$CO_SELF_IMPROVE_SKILL" \
    "session.*情報|対象.*session|target.*session|セッション.*情報"
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "spawn プロンプトから対象 session 情報を受け取る記述がある" test_spawn_receives_session_info
else
  run_test_skip "対象 session 情報受取" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# Test: spawn 時プロンプトから「タスク内容」を受け取る記述がある
test_spawn_receives_task_content() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  assert_file_contains "$CO_SELF_IMPROVE_SKILL" \
    "タスク.*内容|task.*content|タスク.*情報"
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "spawn プロンプトからタスク内容を受け取る記述がある" test_spawn_receives_task_content
else
  run_test_skip "タスク内容受取" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# Test: spawn 時プロンプトから「観察モード」を受け取る記述がある
test_spawn_receives_observation_mode() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  assert_file_contains "$CO_SELF_IMPROVE_SKILL" \
    "観察.*モード|observation.*mode|observe.*mode|観察モード"
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "spawn プロンプトから観察モードを受け取る記述がある" test_spawn_receives_observation_mode
else
  run_test_skip "観察モード受取" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# Test: scenario-run / retrospect / test-project-manage の内部フロー参照がある
test_internal_flows_referenced() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  assert_file_contains "$CO_SELF_IMPROVE_SKILL" \
    "scenario-run|retrospect|test-project-manage"
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "内部フロー（scenario-run / retrospect / test-project-manage）が参照されている" test_internal_flows_referenced
else
  run_test_skip "内部フロー参照" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# Edge case: spawn 受取セクションが SKILL.md の先頭セクションにある（frontmatter 除く）
test_spawn_section_near_top() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  python3 - "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# frontmatter を除去（--- ... --- ブロック）
content_no_fm = re.sub(r'^---.*?---\s*', '', content, flags=re.DOTALL)
lines = content_no_fm.split('\n')

# 最初の見出しを探す
for i, line in enumerate(lines):
    if re.match(r'^#{1,3}\s+', line):
        # 最初の見出しが spawn 関連かチェック
        if re.search(r'spawn|受取|受信|起動.*受', line, re.IGNORECASE):
            sys.exit(0)
        # 最初の見出しが spawn 以外でも、その後 50 行以内に spawn 記述があるかチェック
        head_content = '\n'.join(lines[i:i+50])
        if re.search(r'spawn|受取|受信', head_content, re.IGNORECASE):
            sys.exit(0)
        # 最初の見出しより先にスキップ
        break

# fallback: ファイル全体の前半（40%）に spawn 記述があるか
total = len(lines)
front_half = '\n'.join(lines[:max(1, total * 2 // 5)])
if re.search(r'spawn.*受取|受取.*spawn|spawn.*手順', front_half, re.IGNORECASE):
    sys.exit(0)

print("spawn procedure section not found near top of file", file=sys.stderr)
sys.exit(1)
PYEOF
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "[edge] spawn 受取セクションが SKILL.md の前半に位置する" test_spawn_section_near_top
else
  run_test_skip "[edge] spawn 受取セクション位置" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# Scenario: Skill() 直接呼出し記述の削除 (spec.md line 11)
# WHEN: co-self-improve SKILL.md を参照する
# THEN: Skill(twl:co-self-improve) による直接呼出しに依存した記述が存在してはならない（SHALL NOT）

# Test: Skill(twl:co-self-improve) による直接呼出し記述が存在しない
test_no_skill_direct_call_in_self_improve() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  assert_file_not_contains "$CO_SELF_IMPROVE_SKILL" \
    "Skill\s*\(\s*twl:co-self-improve\s*\)"
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "Skill(twl:co-self-improve) 直接呼出し記述が存在しない" test_no_skill_direct_call_in_self_improve
else
  run_test_skip "Skill() 直接呼出しなし" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# Edge case: cld-spawn を使った起動方法の記述がある（直接呼出しの代替として）
test_cld_spawn_in_self_improve() {
  assert_file_exists "$CO_SELF_IMPROVE_SKILL" || return 1
  assert_file_contains "$CO_SELF_IMPROVE_SKILL" "cld-spawn"
}

if [[ -f "${PROJECT_ROOT}/${CO_SELF_IMPROVE_SKILL}" ]]; then
  run_test "[edge] cld-spawn を使った起動方法の記述がある" test_cld_spawn_in_self_improve
else
  run_test_skip "[edge] cld-spawn 記述" "${CO_SELF_IMPROVE_SKILL} not yet created"
fi

# =============================================================================
# Requirement: deps.yaml の su-observer.supervises 更新
# Scenario: deps.yaml の整合性確認 (spec.md line 19)
# WHEN: twl check で deps.yaml を検証する
# THEN: su-observer.supervises に co-self-improve が含まれており、
#       co-self-improve.spawnable_by に su-observer が含まれている（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml の su-observer.supervises 更新 ---"

# Test: su-observer.supervises に co-self-improve が含まれている
test_su_observer_supervises_co_self_improve() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_list_contains "$DEPS_YAML" "
skills = data.get('skills', {})
su = skills.get('su-observer', {})
supervises = su.get('supervises', [])
if 'co-self-improve' not in supervises:
    print(f'co-self-improve not in su-observer.supervises: {supervises}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "su-observer.supervises に co-self-improve が含まれている" test_su_observer_supervises_co_self_improve
else
  run_test_skip "su-observer.supervises co-self-improve" "${DEPS_YAML} not yet created"
fi

# Test: co-self-improve.spawnable_by に su-observer が含まれている
test_co_self_improve_spawnable_by_su_observer() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_list_contains "$DEPS_YAML" "
skills = data.get('skills', {})
csi = skills.get('co-self-improve', {})
spawnable_by = csi.get('spawnable_by', [])
if 'su-observer' not in spawnable_by:
    print(f'su-observer not in co-self-improve.spawnable_by: {spawnable_by}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "co-self-improve.spawnable_by に su-observer が含まれている" test_co_self_improve_spawnable_by_su_observer
else
  run_test_skip "co-self-improve.spawnable_by su-observer" "${DEPS_YAML} not yet created"
fi

# Test: deps.yaml が valid YAML である
test_deps_valid_yaml() {
  assert_valid_yaml "$DEPS_YAML"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml が valid YAML である" test_deps_valid_yaml
else
  run_test_skip "deps.yaml YAML valid" "${DEPS_YAML} not yet created"
fi

# Edge case: supervises と spawnable_by の双方向整合性（非対称性解消）
test_supervises_spawnable_by_symmetric() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_list_contains "$DEPS_YAML" "
skills = data.get('skills', {})
su = skills.get('su-observer', {})
csi = skills.get('co-self-improve', {})

supervises = su.get('supervises', [])
spawnable_by = csi.get('spawnable_by', [])

errors = []
if 'co-self-improve' not in supervises:
    errors.append('co-self-improve not in su-observer.supervises')
if 'su-observer' not in spawnable_by:
    errors.append('su-observer not in co-self-improve.spawnable_by')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "[edge] supervises と spawnable_by の双方向整合性が保たれている" test_supervises_spawnable_by_symmetric
else
  run_test_skip "[edge] 双方向整合性" "${DEPS_YAML} not yet created"
fi

# Edge case: co-self-improve が deps.yaml に存在する（エントリ自体の存在確認）
test_co_self_improve_entry_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_list_contains "$DEPS_YAML" "
skills = data.get('skills', {})
if 'co-self-improve' not in skills:
    print('co-self-improve entry missing from deps.yaml skills', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "[edge] co-self-improve エントリが deps.yaml に存在する" test_co_self_improve_entry_exists
else
  run_test_skip "[edge] co-self-improve エントリ存在" "${DEPS_YAML} not yet created"
fi

# Edge case: su-observer の supervises リストに全 controller が含まれている
# (co-autopilot, co-issue, co-architect, co-project, co-utility, co-self-improve)
test_su_observer_supervises_all_controllers() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_list_contains "$DEPS_YAML" "
skills = data.get('skills', {})
su = skills.get('su-observer', {})
supervises = su.get('supervises', [])
required = ['co-autopilot', 'co-issue', 'co-architect', 'co-project', 'co-utility', 'co-self-improve']
missing = [c for c in required if c not in supervises]
if missing:
    print(f'missing controllers in su-observer.supervises: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "[edge] su-observer.supervises に全 controller が含まれている" test_su_observer_supervises_all_controllers
else
  run_test_skip "[edge] su-observer 全 controller supervises" "${DEPS_YAML} not yet created"
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
