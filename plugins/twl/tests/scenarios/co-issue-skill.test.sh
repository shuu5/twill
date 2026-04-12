#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-issue SKILL.md
# Generated from: deltaspec/changes/c-1-controller-migration/specs/co-issue/spec.md
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

SKILL_MD="skills/co-issue/SKILL.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: co-issue SKILL.md 4 Phase フロー実装
# =============================================================================
echo ""
echo "--- Requirement: co-issue SKILL.md 4 Phase フロー実装 ---"

# Scenario: 単一 Issue 作成 (line 14)
# WHEN: ユーザーが要望を伝え、分解判断で単一 Issue と判定される
# THEN: Phase 3 で 1 件の精緻化を実行し、Phase 4 で issue-create が呼ばれる

# Test: SKILL.md が stub ではなく完全実装されている
test_skill_not_stub() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "C-1\s+以降で実装" || return 1
  assert_file_not_contains "$SKILL_MD" "^（C-1\s+以降で\s*Phase" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md が stub ではない（C-1 以降で実装 の記述なし）" test_skill_not_stub
else
  run_test_skip "SKILL.md が stub ではない" "skills/co-issue/SKILL.md not yet created"
fi

# Test: 4 Phase 構成が存在する
test_four_phases_exist() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*1" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*2" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*3" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*4" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "4 Phase 構成（Phase 1-4）が存在する" test_four_phases_exist
else
  run_test_skip "4 Phase 構成が存在する" "skills/co-issue/SKILL.md not yet created"
fi

# Edge case: Phase 5 以上が存在しない（4 Phase のみ）
test_no_phase_5_or_above() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "Phase\s*[5-9]" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 構成 [edge: Phase 5 以上が存在しない]" test_no_phase_5_or_above
else
  run_test_skip "Phase 構成 [edge: Phase 5 以上が存在しない]" "skills/co-issue/SKILL.md not yet created"
fi

# Test: Phase 1 - 問題探索（/twl:explore 呼び出し）
test_phase1_explore() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "対話的問題探索" || return 1
  assert_file_contains "$SKILL_MD" "explore-summary" || return 1
  assert_file_contains "$SKILL_MD" "Read/Grep/Glob" || return 1
  assert_file_contains "$SKILL_MD" "ユーザーに直接提示" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 1 - 対話的問題探索（inline 探索 / explore-summary 記述）" test_phase1_explore
else
  run_test_skip "Phase 1 - 対話的問題探索" "skills/co-issue/SKILL.md not yet created"
fi

# Test: Phase 2 - 分解判断（単一 vs 複数）
test_phase2_decomposition() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "分解|decompos|単一|複数|single|multiple"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 2 - 分解判断（単一 vs 複数）記述" test_phase2_decomposition
else
  run_test_skip "Phase 2 - 分解判断" "skills/co-issue/SKILL.md not yet created"
fi

# Test: Phase 3 - Per-Issue 精緻化（Level-based dispatch via issue-lifecycle-orchestrator）
test_phase3_refinement_loop() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Level-based dispatch" || return 1
  assert_file_contains "$SKILL_MD" "issue-lifecycle-orchestrator" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 3 - Per-Issue 精緻化（Level-based dispatch）" test_phase3_refinement_loop
else
  run_test_skip "Phase 3 - Per-Issue 精緻化" "skills/co-issue/SKILL.md not yet created"
fi

# Edge case: Phase 3 が workflow-issue-lifecycle を参照する記述がある
test_phase3_workflow_delegation() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "workflow-issue-lifecycle" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 3 [edge: workflow-issue-lifecycle への委譲記述]" test_phase3_workflow_delegation
else
  run_test_skip "Phase 3 [edge: workflow-issue-lifecycle への委譲記述]" "skills/co-issue/SKILL.md not yet created"
fi

# Test: Phase 4 - Aggregate & Present
test_phase4_create() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "report.json" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 4 - Aggregate & Present 記述" test_phase4_create
else
  run_test_skip "Phase 4 - Aggregate & Present" "skills/co-issue/SKILL.md not yet created"
fi

# Scenario: 複数 Issue 分解 (line 18)
# WHEN: 分解判断で複数 Issue が必要と判定される
# THEN: Phase 3 で各候補に対して Level-based dispatch が実行され、Phase 4 で aggregate される
# (旧 workflow-issue-create/workflow-issue-refine は v2 cutover で削除済み)

WORKFLOW_SKILL_MD="skills/workflow-issue-lifecycle/SKILL.md"

# =============================================================================
# Requirement: explore-summary 検出による Phase 1 スキップ
# =============================================================================
echo ""
echo "--- Requirement: explore-summary 検出による Phase 1 スキップ ---"

# Scenario: explore-summary が存在する場合 (line 27)
# WHEN: .controller-issue/explore-summary.md が存在する
# THEN: AskUserQuestion で「継続する / 最初から」の選択肢が提示され、「継続」選択時は Phase 2 から開始される

test_explore_summary_detection() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "explore-summary\.md"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "explore-summary.md 検出ロジック記述" test_explore_summary_detection
else
  run_test_skip "explore-summary.md 検出ロジック" "skills/co-issue/SKILL.md not yet created"
fi

test_explore_summary_choice() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "継続|最初から|AskUserQuestion"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "explore-summary 存在時の選択肢提示" test_explore_summary_choice
else
  run_test_skip "explore-summary 存在時の選択肢提示" "skills/co-issue/SKILL.md not yet created"
fi

# Edge case: .controller-issue/<session-id>/ セッションIDサブディレクトリの記述
test_controller_issue_dir_path() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "\.controller-issue/"
}

# Edge case: セッションIDによるディレクトリ分離の記述
test_controller_issue_session_id() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "session.id|SESSION_ID|session-id|SESSION_DIR"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "explore-summary [edge: .controller-issue/ パスの正確な記述]" test_controller_issue_dir_path
  run_test "explore-summary [edge: セッションIDによるディレクトリ分離]" test_controller_issue_session_id
else
  run_test_skip "explore-summary [edge: .controller-issue/ パス]" "skills/co-issue/SKILL.md not yet created"
  run_test_skip "explore-summary [edge: セッションIDディレクトリ分離]" "skills/co-issue/SKILL.md not yet created"
fi

# Scenario: explore-summary が存在しない場合 (line 31)
# WHEN: .controller-issue/explore-summary.md が存在しない
# THEN: 通常の Phase 1（問題探索）から開始される

# Edge case: explore-summary 不在時は Phase 1 から開始する旨の記述
test_explore_summary_absent_fallback() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*1|通常|探索"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "explore-summary 不在時 [edge: Phase 1 から開始する記述]" test_explore_summary_absent_fallback
else
  run_test_skip "explore-summary 不在時 [edge: Phase 1 から開始]" "skills/co-issue/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: TaskCreate による Phase 進捗管理
# =============================================================================
echo ""
echo "--- Requirement: TaskCreate による Phase 進捗管理 ---"

# Scenario: 4 Phase の進捗追跡 (line 39)
# WHEN: co-issue が起動される
# THEN: Phase 1-4 のタスクが順次登録・更新され、ユーザーが CLI 上で進捗を確認できる

test_task_create_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskCreate|task.*create|タスク.*登録"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskCreate によるPhaseタスク登録の記述" test_task_create_mention
else
  run_test_skip "TaskCreate によるPhaseタスク登録" "skills/co-issue/SKILL.md not yet created"
fi

test_task_update_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskUpdate|task.*update|タスク.*更新|completed"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskUpdate による Phase 完了更新の記述" test_task_update_mention
else
  run_test_skip "TaskUpdate による Phase 完了更新" "skills/co-issue/SKILL.md not yet created"
fi

# Edge case: TaskCreate と TaskUpdate がペアで存在
test_task_create_update_pair() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskCreate|task.*create" || return 1
  assert_file_contains "$SKILL_MD" "TaskUpdate|task.*update" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskCreate/TaskUpdate [edge: 両方がペアで存在]" test_task_create_update_pair
else
  run_test_skip "TaskCreate/TaskUpdate [edge: ペア]" "skills/co-issue/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: Phase 4 完了後のクリーンアップ（co-issue inline / workflow-issue-lifecycle 側で実行）
# =============================================================================
echo ""
echo "--- Requirement: Phase 4 完了後のクリーンアップ ---"

# Scenario: Issue 作成完了 (line 47)
# WHEN: Phase 4 で Issue 作成が成功する
# THEN: .controller-issue/ が削除され、Issue URL と次のステップが表示される
# Note: 旧 workflow-issue-create は v2 cutover (#493) で削除済み。
#       クリーンアップは workflow-issue-lifecycle / co-issue 側で実行。

test_cleanup_in_workflow() {
  assert_file_exists "$WORKFLOW_SKILL_MD" || return 1
  assert_file_contains "$WORKFLOW_SKILL_MD" "controller-issue|cleanup|STATE"
}

if [[ -f "${PROJECT_ROOT}/${WORKFLOW_SKILL_MD}" ]]; then
  run_test "workflow-issue-lifecycle に controller-issue 関連の記述" test_cleanup_in_workflow
else
  run_test_skip "controller-issue 関連の記述" "skills/workflow-issue-lifecycle/SKILL.md not yet created"
fi

test_issue_url_in_workflow() {
  assert_file_exists "$WORKFLOW_SKILL_MD" || return 1
  assert_file_contains "$WORKFLOW_SKILL_MD" "URL|url|issue_url|report"
}

if [[ -f "${PROJECT_ROOT}/${WORKFLOW_SKILL_MD}" ]]; then
  run_test "workflow-issue-lifecycle に Issue URL 関連の記述" test_issue_url_in_workflow
else
  run_test_skip "Issue URL 関連の記述" "skills/workflow-issue-lifecycle/SKILL.md not yet created"
fi

# Edge case: YAML frontmatter に type: controller が記述
test_frontmatter_controller_type() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "type:\s*controller"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: frontmatter type: controller]" test_frontmatter_controller_type
else
  run_test_skip "SKILL.md [edge: frontmatter type: controller]" "skills/co-issue/SKILL.md not yet created"
fi

# =============================================================================
# deps.yaml co-issue can_spawn 検証
# =============================================================================
echo ""
echo "--- deps.yaml co-issue can_spawn 検証 ---"

# spec 要件: co-issue の can_spawn に atomic を追加（issue-create, issue-structure 等）
test_co_issue_can_spawn_atomic() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ci = skills.get('co-issue', {})
cs = ci.get('can_spawn', [])
if 'atomic' not in cs:
    print(f'can_spawn={cs}, missing atomic', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-issue can_spawn に atomic 含む" test_co_issue_can_spawn_atomic

# Edge case: can_spawn がリスト型
test_co_issue_can_spawn_is_list() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ci = skills.get('co-issue', {})
cs = ci.get('can_spawn')
if not isinstance(cs, list):
    print(f'can_spawn is {type(cs).__name__}, expected list', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-issue can_spawn [edge: リスト型]" test_co_issue_can_spawn_is_list

# Edge case: can_spawn に reference が含まれている（テンプレート参照のため）
test_co_issue_can_spawn_reference() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ci = skills.get('co-issue', {})
cs = ci.get('can_spawn', [])
if 'reference' not in cs:
    print(f'can_spawn={cs}, missing reference', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-issue can_spawn [edge: reference 含む（テンプレート参照）]" test_co_issue_can_spawn_reference

# =============================================================================
# Requirement: explore ループ構造の静的テストケース追加 (issue-489)
# =============================================================================
echo ""
echo "--- Requirement: explore ループ構造の静的テストケース追加 ---"

# Scenario: ケース 1 — 1 ループで Phase 2 へ進むゲート記述
# WHEN: co-issue-skill.test.sh を実行する
# THEN: SKILL.md に「1 ループで Phase 2 へ進む」ゲート選択肢の記述があることを grep で検証し PASS する

test_summary_gate_phase2_option() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "summary-gate|Phase 2 へ進む|Phase 2 に進む"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "ケース 1: summary-gate に Phase 2 へ進む選択肢の記述" test_summary_gate_phase2_option
else
  run_test_skip "ケース 1: summary-gate に Phase 2 へ進む選択肢" "skills/co-issue/SKILL.md not yet created"
fi

# Scenario: ケース 2 — summary 修正ループ記述
# WHEN: co-issue-skill.test.sh を実行する
# THEN: SKILL.md に summary 修正の再提示ループ記述があることを grep で検証し PASS する

test_summary_gate_modify() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "summary を修正|修正して再提示|summary-gate に戻る"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "ケース 2: summary 修正ループの記述" test_summary_gate_modify
else
  run_test_skip "ケース 2: summary 修正ループ" "skills/co-issue/SKILL.md not yet created"
fi

# Scenario: ケース 3 — 手動編集対応記述（edit-complete-gate 含む）
# WHEN: co-issue-skill.test.sh を実行する
# THEN: SKILL.md に edit-complete-gate の記述があることを grep で検証し PASS する

test_edit_complete_gate() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "edit-complete-gate"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "ケース 3: edit-complete-gate の記述" test_edit_complete_gate
else
  run_test_skip "ケース 3: edit-complete-gate の記述" "skills/co-issue/SKILL.md not yet created"
fi

# Scenario: ケース 4 — Step 1.5 のループ外配置
# WHEN: co-issue-skill.test.sh を実行する
# THEN: SKILL.md に Step 1.5 が loop-gate の [A] 選択後（ループ外）に配置されていることを grep で検証し PASS する

test_step_1_5_outside_loop() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Step 1\.5"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "ケース 4: Step 1.5 の記述" test_step_1_5_outside_loop
else
  run_test_skip "ケース 4: Step 1.5 の記述" "skills/co-issue/SKILL.md not yet created"
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
