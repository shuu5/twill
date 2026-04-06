#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-project SKILL.md
# Generated from: deltaspec/changes/c-1-controller-migration/specs/co-project/spec.md
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

SKILL_MD="skills/co-project/SKILL.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: co-project SKILL.md 3モードルーティング実装
# =============================================================================
echo ""
echo "--- Requirement: co-project SKILL.md 3モードルーティング実装 ---"

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
  run_test_skip "SKILL.md が stub ではない" "skills/co-project/SKILL.md not yet created"
fi

# Test: 3 モード（create / migrate / snapshot）が全て記述されている
test_three_modes_exist() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "create" || return 1
  assert_file_contains "$SKILL_MD" "migrate" || return 1
  assert_file_contains "$SKILL_MD" "snapshot" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "3 モード（create / migrate / snapshot）が存在する" test_three_modes_exist
else
  run_test_skip "3 モードが存在する" "skills/co-project/SKILL.md not yet created"
fi

# Test: Step 0 モード判定の記述
test_step0_mode_routing() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Step\s*0|モード判定|mode.*判定|routing"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Step 0 モード判定の記述" test_step0_mode_routing
else
  run_test_skip "Step 0 モード判定" "skills/co-project/SKILL.md not yet created"
fi

# Scenario: create モード実行 (line 14)
# WHEN: ユーザーが create モードで co-project を呼び出す
# THEN: プロジェクト名・テンプレートタイプの確認後、project-create → governance 適用 → Board 作成が実行される

test_create_mode_project_create() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "project-create"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "create モード - project-create の記述" test_create_mode_project_create
else
  run_test_skip "create モード - project-create" "skills/co-project/SKILL.md not yet created"
fi

test_create_mode_governance() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "governance"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "create モード - governance 適用の記述" test_create_mode_governance
else
  run_test_skip "create モード - governance 適用" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: create モードのステップ数（Step 1-4）
test_create_mode_steps() {
  assert_file_exists "$SKILL_MD" || return 1
  # create モードが複数ステップを持つことを確認
  assert_file_contains "$SKILL_MD" "入力確認|テンプレート|template" || return 1
  assert_file_contains "$SKILL_MD" "完了.*レポート|レポート|report" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "create モード [edge: 入力確認〜完了レポートのステップ]" test_create_mode_steps
else
  run_test_skip "create モード [edge: ステップ構成]" "skills/co-project/SKILL.md not yet created"
fi

# Scenario: migrate モード実行 (line 18)
# WHEN: ユーザーが migrate モードで co-project を呼び出す
# THEN: 現在のプロジェクト位置が確認され、project-migrate → governance 再適用が実行される

test_migrate_mode_project_migrate() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "project-migrate"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "migrate モード - project-migrate の記述" test_migrate_mode_project_migrate
else
  run_test_skip "migrate モード - project-migrate" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: migrate モードに「現在地確認」ステップの記述
test_migrate_mode_current_position() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "現在地|現在.*位置|current.*position|current.*state"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "migrate モード [edge: 現在地確認ステップの記述]" test_migrate_mode_current_position
else
  run_test_skip "migrate モード [edge: 現在地確認ステップ]" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: migrate モードに governance 再適用の記述
test_migrate_mode_governance_reapply() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "governance.*再|re.*governance|governance.*reapply|再適用"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "migrate モード [edge: governance 再適用の記述]" test_migrate_mode_governance_reapply
else
  run_test_skip "migrate モード [edge: governance 再適用]" "skills/co-project/SKILL.md not yet created"
fi

# Scenario: snapshot モード実行 (line 22)
# WHEN: ユーザーが snapshot モードで co-project を呼び出す
# THEN: ソースプロジェクトの分析 → Tier 分類 → テンプレート生成が実行される

test_snapshot_mode_analyze() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "snapshot-analyze|snapshot.*分析|analyze"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "snapshot モード - 分析ステップの記述" test_snapshot_mode_analyze
else
  run_test_skip "snapshot モード - 分析ステップ" "skills/co-project/SKILL.md not yet created"
fi

test_snapshot_mode_classify() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "snapshot-classify|Tier|tier|classify"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "snapshot モード - Tier 分類ステップの記述" test_snapshot_mode_classify
else
  run_test_skip "snapshot モード - Tier 分類ステップ" "skills/co-project/SKILL.md not yet created"
fi

test_snapshot_mode_generate() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "snapshot-generate|テンプレート生成|generate"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "snapshot モード - テンプレート生成ステップの記述" test_snapshot_mode_generate
else
  run_test_skip "snapshot モード - テンプレート生成ステップ" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: snapshot モードのステップ数（Step 1-5）が最も多い
test_snapshot_mode_step_count() {
  assert_file_exists "$SKILL_MD" || return 1
  # snapshot-analyze, snapshot-classify, snapshot-generate の 3 つが最低限存在
  local count=0
  grep -qiP "snapshot-analyze" "${PROJECT_ROOT}/${SKILL_MD}" && ((count++)) || true
  grep -qiP "snapshot-classify" "${PROJECT_ROOT}/${SKILL_MD}" && ((count++)) || true
  grep -qiP "snapshot-generate" "${PROJECT_ROOT}/${SKILL_MD}" && ((count++)) || true
  [[ $count -ge 3 ]]
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "snapshot モード [edge: 3 サブステップ全てが記述]" test_snapshot_mode_step_count
else
  run_test_skip "snapshot モード [edge: サブステップ数]" "skills/co-project/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: plugin 管理の co-project テンプレート統合
# =============================================================================
echo ""
echo "--- Requirement: plugin 管理の co-project テンプレート統合 ---"

# Scenario: plugin テンプレートでのプロジェクト作成 (line 31)
# WHEN: create モードで --type plugin が指定される
# THEN: plugin テンプレートが適用され、通常のプロジェクト作成フローで plugin プロジェクトが構築される

test_plugin_type_mention() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "plugin|--type"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "plugin テンプレート / --type の記述" test_plugin_type_mention
else
  run_test_skip "plugin テンプレート / --type の記述" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: 専用 controller を設けない旨（plugin は co-project 経由）
test_no_dedicated_plugin_controller() {
  assert_file_exists "$SKILL_MD" || return 1
  # co-project が plugin を扱うこと、かつ create モードとして統合されていること
  assert_file_contains "$SKILL_MD" "create" || return 1
  assert_file_contains "$SKILL_MD" "plugin|テンプレート" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "plugin 統合 [edge: create モードとして統合]" test_no_dedicated_plugin_controller
else
  run_test_skip "plugin 統合 [edge: create モードとして統合]" "skills/co-project/SKILL.md not yet created"
fi

# =============================================================================
# Requirement: create モードの Rich Mode 対応
# =============================================================================
echo ""
echo "--- Requirement: create モードの Rich Mode 対応 ---"

# Scenario: Rich Mode テンプレートでの作成 (line 38)
# WHEN: テンプレートに manifest.yaml が存在する
# THEN: スタック情報テーブルが表示され、containers セクション存在時は container-dependency-check が実行される

test_rich_mode_manifest() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "manifest\.yaml|Rich\s*Mode"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Rich Mode - manifest.yaml の記述" test_rich_mode_manifest
else
  run_test_skip "Rich Mode - manifest.yaml の記述" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: container-dependency-check への言及
test_container_dependency_check() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "container-dependency-check|container.*check|containers"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Rich Mode [edge: container-dependency-check への言及]" test_container_dependency_check
else
  run_test_skip "Rich Mode [edge: container-dependency-check]" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: スタック情報テーブル表示への言及
test_stack_info_table() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "スタック.*テーブル|stack.*table|スタック情報"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Rich Mode [edge: スタック情報テーブル表示]" test_stack_info_table
else
  run_test_skip "Rich Mode [edge: スタック情報テーブル表示]" "skills/co-project/SKILL.md not yet created"
fi

# Edge case: YAML frontmatter に type: controller が記述
test_frontmatter_controller_type() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "type:\s*controller"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md [edge: frontmatter type: controller]" test_frontmatter_controller_type
else
  run_test_skip "SKILL.md [edge: frontmatter type: controller]" "skills/co-project/SKILL.md not yet created"
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
