#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-autopilot SKILL.md
# Generated from: openspec/changes/c-1-controller-migration/specs/co-autopilot/spec.md
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

SKILL_MD="skills/co-autopilot/SKILL.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: co-autopilot SKILL.md 実装
# =============================================================================
echo ""
echo "--- Requirement: co-autopilot SKILL.md 実装 ---"

# Scenario: 通常の autopilot 実行 (line 16)
# WHEN: ユーザーが /dev:co-autopilot を実行し、対象 Issue 群が存在する
# THEN: plan.yaml が生成され、Phase ループで全 Issue が処理され、autopilot-summary が出力される

# Test: SKILL.md が stub ではなく完全実装されている
test_skill_not_stub() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "C-1\s+以降で実装" || return 1
  assert_file_not_contains "$SKILL_MD" "^（C-1" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md が stub ではない（C-1 以降で実装 の記述なし）" test_skill_not_stub
else
  run_test_skip "SKILL.md が stub ではない" "skills/co-autopilot/SKILL.md not yet created"
fi

# Test: Step 0-5 構成が存在する
test_step_structure() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*0" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*1" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*2" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*3" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*4" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*5" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 0-5 構成が存在する" test_step_structure
else
  run_test_skip "Step 0-5 構成が存在する" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: Step 6 以上が存在しない（0-5 のみ）
test_no_step_6_or_above() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "Step\s*[6-9]" || return 1
  assert_file_not_contains "$SKILL_MD" "Step\s*1[0-9]" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 構成 [edge: Step 6 以上が存在しない]" test_no_step_6_or_above
else
  run_test_skip "Step 構成 [edge: Step 6 以上が存在しない]" "skills/co-autopilot/SKILL.md not yet created"
fi

# Test: plan.yaml 生成への言及（autopilot-plan スクリプト呼び出し）
test_plan_yaml_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "plan\.yaml|autopilot-plan"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "plan.yaml 生成 / autopilot-plan への言及" test_plan_yaml_mention
else
  run_test_skip "plan.yaml 生成 / autopilot-plan への言及" "skills/co-autopilot/SKILL.md not yet created"
fi

# Test: Phase ループの記述
test_phase_loop_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase" || return 1
  assert_file_contains "$SKILL_MD" "autopilot-phase-execute|phase.execute|phase-execute" || return 1
  assert_file_contains "$SKILL_MD" "autopilot-phase-postprocess|phase.postprocess|phase-postprocess" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase ループの記述（execute + postprocess）" test_phase_loop_mention
else
  run_test_skip "Phase ループの記述" "skills/co-autopilot/SKILL.md not yet created"
fi

# Test: autopilot-summary 呼び出しの記述
test_summary_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "autopilot-summary|summary"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "autopilot-summary 呼び出しの記述" test_summary_mention
else
  run_test_skip "autopilot-summary 呼び出しの記述" "skills/co-autopilot/SKILL.md not yet created"
fi

# Scenario: --auto フラグ付き実行 (line 20)
# WHEN: --auto フラグが指定されている
# THEN: 計画承認ステップがスキップされ、自動的に Phase ループに進む

test_auto_flag_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "--auto"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "--auto フラグの記述" test_auto_flag_mention
else
  run_test_skip "--auto フラグの記述" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: --auto 時のスキップ/自動承認ロジックの記述
test_auto_skip_approval() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "自動承認|skip|スキップ|auto.*approv"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "--auto [edge: 自動承認/スキップロジック記述]" test_auto_skip_approval
else
  run_test_skip "--auto [edge: 自動承認/スキップロジック記述]" "skills/co-autopilot/SKILL.md not yet created"
fi

# Scenario: Phase 内 Issue 失敗時 (line 24)
# WHEN: Phase N で Issue が failed になる
# THEN: 不変条件 D に従い、依存先の後続 Phase Issue が自動 skip される

test_failure_handling() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "fail|failed"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Issue 失敗時の挙動記述" test_failure_handling
else
  run_test_skip "Issue 失敗時の挙動記述" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: 依存先 skip の記述
test_dependency_skip() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "依存|depend|skip|スキップ"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "失敗時 [edge: 依存先 skip の記述]" test_dependency_skip
else
  run_test_skip "失敗時 [edge: 依存先 skip の記述]" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: 引数解析（Step 0）に MODE 判定の記述
test_step0_mode_parsing() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "MODE|引数|パース|parse"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 0 [edge: MODE 判定 / 引数パース記述]" test_step0_mode_parsing
else
  run_test_skip "Step 0 [edge: MODE 判定 / 引数パース記述]" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: AskUserQuestion による計画承認
test_ask_user_question() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "AskUserQuestion|ユーザー.*確認|承認"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 2 [edge: AskUserQuestion / ユーザー確認記述]" test_ask_user_question
else
  run_test_skip "Step 2 [edge: AskUserQuestion / ユーザー確認記述]" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: autopilot-init スクリプト呼び出しの記述
test_autopilot_init_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "autopilot-init"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 3 [edge: autopilot-init スクリプト記述]" test_autopilot_init_mention
else
  run_test_skip "Step 3 [edge: autopilot-init スクリプト記述]" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: YAML frontmatter に type: controller が記述
test_frontmatter_controller_type() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "type:\s*controller"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: frontmatter type: controller]" test_frontmatter_controller_type
else
  run_test_skip "SKILL.md [edge: frontmatter type: controller]" "skills/co-autopilot/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: self-improve ECC 照合の統合
# =============================================================================
echo ""
echo "--- Requirement: self-improve ECC 照合の統合 ---"

# Scenario: self-improve Issue 検出時 (line 34)
# WHEN: autopilot-patterns が self-improve Issue 候補を検出する
# THEN: ECC 照合が実行され、合致する場合は session.json の self_improve_issues に記録される

test_self_improve_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "self.improve|self_improve"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "self-improve Issue 検出の記述" test_self_improve_mention
else
  run_test_skip "self-improve Issue 検出の記述" "skills/co-autopilot/SKILL.md not yet created"
fi

test_ecc_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "ECC|error.correction"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "ECC 照合への言及" test_ecc_mention
else
  run_test_skip "ECC 照合への言及" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: session.json の self_improve_issues フィールドへの言及
test_session_self_improve_field() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "self_improve_issues|self-improve.*session"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "ECC [edge: session.json self_improve_issues フィールド言及]" test_session_self_improve_field
else
  run_test_skip "ECC [edge: session.json self_improve_issues フィールド言及]" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: autopilot-patterns への言及
test_autopilot_patterns_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "autopilot-patterns"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "ECC [edge: autopilot-patterns への言及]" test_autopilot_patterns_mention
else
  run_test_skip "ECC [edge: autopilot-patterns への言及]" "skills/co-autopilot/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: TaskCreate による進捗管理
# =============================================================================
echo ""
echo "--- Requirement: TaskCreate による進捗管理 ---"

# Scenario: Phase 進捗の可視化 (line 43)
# WHEN: Phase 1 が開始される
# THEN: TaskCreate で「Phase 1: Issue #X, #Y」タスクが登録され、各 Issue 完了時に TaskUpdate で更新される

test_task_create_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskCreate|task.*create|タスク.*登録"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskCreate による Phase タスク登録の記述" test_task_create_mention
else
  run_test_skip "TaskCreate による Phase タスク登録の記述" "skills/co-autopilot/SKILL.md not yet created"
fi

test_task_update_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskUpdate|task.*update|タスク.*更新|completed"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskUpdate による Issue 完了時更新の記述" test_task_update_mention
else
  run_test_skip "TaskUpdate による Issue 完了時更新の記述" "skills/co-autopilot/SKILL.md not yet created"
fi

# Edge case: TaskCreate と TaskUpdate の両方がペアで存在
test_task_create_update_pair() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskCreate|task.*create" || return 1
  assert_file_contains "$SKILL_MD" "TaskUpdate|task.*update" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskCreate/TaskUpdate [edge: 両方がペアで存在]" test_task_create_update_pair
else
  run_test_skip "TaskCreate/TaskUpdate [edge: 両方がペアで存在]" "skills/co-autopilot/SKILL.md not yet created"
fi

# =============================================================================
# deps.yaml co-autopilot can_spawn 検証
# =============================================================================
echo ""
echo "--- deps.yaml co-autopilot can_spawn 検証 ---"

# spec 要件: co-autopilot の can_spawn に composite, atomic, specialist が含まれる
test_co_autopilot_can_spawn_types() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-autopilot', {})
cs = ca.get('can_spawn', [])
required = ['composite', 'atomic', 'specialist']
missing = [t for t in required if t not in cs]
if missing:
    print(f'can_spawn={cs}, missing {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-autopilot can_spawn に composite/atomic/specialist 含む" test_co_autopilot_can_spawn_types

# Edge case: can_spawn がリスト型
test_co_autopilot_can_spawn_is_list() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-autopilot', {})
cs = ca.get('can_spawn')
if not isinstance(cs, list):
    print(f'can_spawn is {type(cs).__name__}, expected list', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-autopilot can_spawn [edge: リスト型]" test_co_autopilot_can_spawn_is_list

# Edge case: 既存の can_spawn 値（composite, atomic, specialist）が失われていない
test_co_autopilot_can_spawn_preserves_existing() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-autopilot', {})
cs = ca.get('can_spawn', [])
# composite, atomic, specialist は元から存在していたはず
missing = [t for t in ['composite', 'atomic', 'specialist'] if t not in cs]
if missing:
    print(f'Missing from can_spawn: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-autopilot can_spawn [edge: 既存値 composite/atomic/specialist 保持]" test_co_autopilot_can_spawn_preserves_existing

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
