#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-architect SKILL.md
# Generated from: openspec/changes/c-1-controller-migration/specs/co-architect/spec.md
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

SKILL_MD="skills/co-architect/SKILL.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: co-architect SKILL.md 対話的設計フロー実装
# =============================================================================
echo ""
echo "--- Requirement: co-architect SKILL.md 対話的設計フロー実装 ---"

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
  run_test_skip "SKILL.md が stub ではない" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 0-8 構成が存在する
test_step_structure() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*0" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*1" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*2" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*3" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*4" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*5" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*6" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*7" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*8" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 0-8 構成が存在する" test_step_structure
else
  run_test_skip "Step 0-8 構成が存在する" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: Step 9 以上が存在しない（0-8 のみ）
test_no_step_9_or_above() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_not_contains "$SKILL_MD" "Step\s*9" || return 1
  assert_file_not_contains "$SKILL_MD" "Step\s*1[0-9]" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 構成 [edge: Step 9 以上が存在しない]" test_no_step_9_or_above
else
  run_test_skip "Step 構成 [edge: Step 9 以上が存在しない]" "skills/co-architect/SKILL.md not yet created"
fi

# Scenario: 通常のアーキテクチャ設計フロー (line 19)
# WHEN: ユーザーが /twl:co-architect を実行する
# THEN: Step 1-8 が順次実行され、architecture/ が構築され、Issue 候補が作成される

# Test: Step 0 - --group モード分岐
test_step0_group_mode() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "--group"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 0 - --group モード分岐の記述" test_step0_group_mode
else
  run_test_skip "Step 0 - --group モード分岐" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 1 - コンテキスト収集
test_step1_context_collection() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "README\.md|CLAUDE\.md|architecture/" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 1 - コンテキスト収集（README/CLAUDE/architecture）" test_step1_context_collection
else
  run_test_skip "Step 1 - コンテキスト収集" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: Step 1 で READ.md, CLAUDE.md, architecture/ の全 3 ソースが言及
test_step1_all_three_sources() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "README" || return 1
  assert_file_contains "$SKILL_MD" "CLAUDE" || return 1
  assert_file_contains "$SKILL_MD" "architecture/" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 1 [edge: README, CLAUDE, architecture/ の全 3 ソース言及]" test_step1_all_three_sources
else
  run_test_skip "Step 1 [edge: 全 3 ソース]" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 2 - 対話的探索（/twl:explore）
test_step2_explore() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "explore"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 2 - 対話的探索（explore）の記述" test_step2_explore
else
  run_test_skip "Step 2 - 対話的探索" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 3 - 完全性チェック
test_step3_completeness() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "architect-completeness-check|完全性.*チェック|completeness"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 3 - 完全性チェック（architect-completeness-check）" test_step3_completeness
else
  run_test_skip "Step 3 - 完全性チェック" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 4 - Phase 計画
test_step4_phase_plan() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "phases/|Phase.*計画|phase.*plan"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 4 - Phase 計画（phases/ への書き込み）" test_step4_phase_plan
else
  run_test_skip "Step 4 - Phase 計画" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 5 - Issue 分解
test_step5_decompose() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "architect-decompose|Issue.*分解|decompose"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 5 - Issue 分解（architect-decompose）" test_step5_decompose
else
  run_test_skip "Step 5 - Issue 分解" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 6 - 整合性チェック（6項目）
test_step6_consistency() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "整合性|consistency|チェック.*6|6.*項目"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 6 - 整合性チェックの記述" test_step6_consistency
else
  run_test_skip "Step 6 - 整合性チェック" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 7 - ユーザー確認
test_step7_user_confirmation() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "ユーザー確認|最終承認|AskUserQuestion|confirm"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 7 - ユーザー確認 / 最終承認の記述" test_step7_user_confirmation
else
  run_test_skip "Step 7 - ユーザー確認" "skills/co-architect/SKILL.md not yet created"
fi

# Test: Step 8 - 一括 Issue 作成
test_step8_issue_create() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "architect-issue-create|一括.*Issue.*作成|issue.*create"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 8 - 一括 Issue 作成（architect-issue-create）" test_step8_issue_create
else
  run_test_skip "Step 8 - 一括 Issue 作成" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: Step 8 で project-board-sync への言及
test_step8_board_sync() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "project-board-sync|board.sync"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 8 [edge: project-board-sync への言及]" test_step8_board_sync
else
  run_test_skip "Step 8 [edge: project-board-sync]" "skills/co-architect/SKILL.md not yet created"
fi

# Scenario: --group モードによるスケルトン Issue 精緻化 (line 23)
# WHEN: --group <context-name> が指定される
# THEN: architect-group-refine が呼び出され、指定 Context のスケルトン Issue 群が一括精緻化される

test_group_refine_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "architect-group-refine|group.refine"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "--group モード - architect-group-refine の記述" test_group_refine_mention
else
  run_test_skip "--group モード - architect-group-refine" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: --group 指定時に Step 1-8 をスキップして終了する旨
test_group_mode_early_exit() {
  assert_file_exists "$SKILL_MD" || return 1
  # --group 時は architect-group-refine を呼び出して終了
  assert_file_contains "$SKILL_MD" "--group" || return 1
  assert_file_contains "$SKILL_MD" "終了|return|exit|スキップ|refine.*呼び出.*終" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "--group モード [edge: 呼び出し後に終了する記述]" test_group_mode_early_exit
else
  run_test_skip "--group モード [edge: 呼び出し後に終了]" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: --group に context-name パラメータの記述
test_group_context_name_param() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "context.name|context|コンテキスト"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "--group モード [edge: context-name パラメータ記述]" test_group_context_name_param
else
  run_test_skip "--group モード [edge: context-name パラメータ]" "skills/co-architect/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: TaskCreate による Step 進捗管理
# =============================================================================
echo ""
echo "--- Requirement: TaskCreate による Step 進捗管理 ---"

# Scenario: 9 Step の進捗追跡 (line 33)
# WHEN: co-architect が起動される
# THEN: 主要 Step のタスクが順次登録・更新される

test_task_create_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskCreate|task.*create|タスク.*登録"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskCreate による Step タスク登録の記述" test_task_create_mention
else
  run_test_skip "TaskCreate による Step タスク登録" "skills/co-architect/SKILL.md not yet created"
fi

test_task_update_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "TaskUpdate|task.*update|タスク.*更新|completed"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "TaskUpdate による Step 完了更新の記述" test_task_update_mention
else
  run_test_skip "TaskUpdate による Step 完了更新" "skills/co-architect/SKILL.md not yet created"
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
  run_test_skip "TaskCreate/TaskUpdate [edge: ペア]" "skills/co-architect/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: architecture/ ファイルへの DDD 構造出力
# =============================================================================
echo ""
echo "--- Requirement: architecture/ ファイルへの DDD 構造出力 ---"

# Scenario: 設計探索結果の永続化 (line 40)
# WHEN: /twl:explore で設計項目が確認される
# THEN: 各項目が architecture/ 配下の対応するファイルに追記・更新される

test_architecture_files_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "architecture/"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "architecture/ 配下のファイルへの記述" test_architecture_files_mention
else
  run_test_skip "architecture/ 配下のファイル記述" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: DDD 構造の主要ファイルが言及されている
test_ddd_structure_files() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "vision\.md|vision" || return 1
  assert_file_contains "$SKILL_MD" "domain/|model|glossary" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "DDD 構造 [edge: vision.md, domain/ 系ファイルへの言及]" test_ddd_structure_files
else
  run_test_skip "DDD 構造 [edge: 主要ファイル]" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: decisions/ ファイルへの言及
test_decisions_dir_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "decisions/"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "DDD 構造 [edge: decisions/ ディレクトリへの言及]" test_decisions_dir_mention
else
  run_test_skip "DDD 構造 [edge: decisions/]" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: contexts/*.md ファイルへの言及
test_contexts_dir_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "contexts/"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "DDD 構造 [edge: contexts/ ディレクトリへの言及]" test_contexts_dir_mention
else
  run_test_skip "DDD 構造 [edge: contexts/]" "skills/co-architect/SKILL.md not yet created"
fi

# Edge case: YAML frontmatter に type: controller が記述
test_frontmatter_controller_type() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "type:\s*controller"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: frontmatter type: controller]" test_frontmatter_controller_type
else
  run_test_skip "SKILL.md [edge: frontmatter type: controller]" "skills/co-architect/SKILL.md not yet created"
fi

# =============================================================================
# deps.yaml co-architect can_spawn 検証
# =============================================================================
echo ""
echo "--- deps.yaml co-architect can_spawn 検証 ---"

# can_spawn に atomic と reference が含まれていることを確認
test_co_architect_can_spawn_atomic() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-architect', {})
cs = ca.get('can_spawn', [])
if 'atomic' not in cs:
    print(f'can_spawn={cs}, missing atomic', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-architect can_spawn に atomic 含む" test_co_architect_can_spawn_atomic

test_co_architect_can_spawn_reference() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-architect', {})
cs = ca.get('can_spawn', [])
if 'reference' not in cs:
    print(f'can_spawn={cs}, missing reference', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-architect can_spawn に reference 含む" test_co_architect_can_spawn_reference

# Edge case: can_spawn がリスト型
test_co_architect_can_spawn_is_list() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ca = skills.get('co-architect', {})
cs = ca.get('can_spawn')
if not isinstance(cs, list):
    print(f'can_spawn is {type(cs).__name__}, expected list', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml co-architect can_spawn [edge: リスト型]" test_co_architect_can_spawn_is_list

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
