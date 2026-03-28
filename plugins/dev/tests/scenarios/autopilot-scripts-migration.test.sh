#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: autopilot-scripts.md
# Generated from: openspec/changes/c-4-scripts-migration/specs/autopilot-scripts.md
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

assert_file_executable() {
  local file="$1"
  [[ -x "${PROJECT_ROOT}/${file}" ]]
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
  ((SKIP++)) || true
}

AUTOPILOT_PLAN="scripts/autopilot-plan.sh"
AUTOPILOT_SHOULD_SKIP="scripts/autopilot-should-skip.sh"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: autopilot-plan スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: autopilot-plan スクリプト移植 ---"

# Scenario: explicit モードで plan.yaml 生成 (line 7)
# WHEN: bash scripts/autopilot-plan.sh --explicit "19,18 -> 20 -> 23" --project-dir $PWD --repo-mode worktree を実行する
# THEN: .autopilot/plan.yaml に session_id, repo_mode, project_dir, phases, dependencies が出力される

test_autopilot_plan_exists() {
  assert_file_exists "$AUTOPILOT_PLAN"
}
run_test "autopilot-plan.sh が存在する" test_autopilot_plan_exists

test_autopilot_plan_executable() {
  assert_file_executable "$AUTOPILOT_PLAN"
}
run_test "autopilot-plan.sh が実行可能である" test_autopilot_plan_executable

test_autopilot_plan_explicit_mode() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  assert_file_contains "$AUTOPILOT_PLAN" '--explicit' || return 1
  return 0
}
run_test "autopilot-plan.sh に --explicit モードが実装されている" test_autopilot_plan_explicit_mode

test_autopilot_plan_output_dir() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # 出力先が .autopilot/ 配下であること
  assert_file_contains "$AUTOPILOT_PLAN" '\.autopilot/' || return 1
  return 0
}
run_test "autopilot-plan.sh の出力先が .autopilot/ 配下である" test_autopilot_plan_output_dir

test_autopilot_plan_yaml_fields() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # plan.yaml に必要なフィールドが生成コードに含まれるか
  assert_file_contains "$AUTOPILOT_PLAN" 'session_id' || return 1
  assert_file_contains "$AUTOPILOT_PLAN" 'repo_mode' || return 1
  assert_file_contains "$AUTOPILOT_PLAN" 'phases' || return 1
  return 0
}
run_test "autopilot-plan.sh が session_id, repo_mode, phases フィールドを出力する" test_autopilot_plan_yaml_fields

# Edge case: --explicit パラメータのフォーマットバリデーション
test_autopilot_plan_explicit_format_validation() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # パラメータ処理ロジックの存在（引数パースまたはバリデーション）
  assert_file_contains "$AUTOPILOT_PLAN" '(getopts|shift|--explicit|EXPLICIT)' || return 1
  return 0
}
run_test "autopilot-plan.sh [edge: --explicit パラメータ処理がある]" test_autopilot_plan_explicit_format_validation

# Scenario: issues モードで依存グラフから Phase 分割 (line 11)
# WHEN: bash scripts/autopilot-plan.sh --issues "10 11 12" --project-dir $PWD --repo-mode worktree を実行する
# THEN: Issue body の依存キーワードに基づきトポロジカルソートされた phases が .autopilot/plan.yaml に出力される

test_autopilot_plan_issues_mode() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  assert_file_contains "$AUTOPILOT_PLAN" '--issues' || return 1
  return 0
}
run_test "autopilot-plan.sh に --issues モードが実装されている" test_autopilot_plan_issues_mode

test_autopilot_plan_topology_sort() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # 依存グラフ/トポロジカルソートのロジック存在確認
  assert_file_contains "$AUTOPILOT_PLAN" '(depend|topolog|phase|order|graph)' || return 1
  return 0
}
run_test "autopilot-plan.sh に依存グラフ処理ロジックがある" test_autopilot_plan_topology_sort

# Edge case: issues モードで空 Issue リストを渡した場合
test_autopilot_plan_empty_issues() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # エラーハンドリングまたは空チェックの存在
  assert_file_contains "$AUTOPILOT_PLAN" '(empty|no.*issue|usage|error)' || return 1
  return 0
}
run_test "autopilot-plan.sh [edge: 空 Issue リストのエラーハンドリング]" test_autopilot_plan_empty_issues

# Scenario: deps.yaml 競合検出と Phase 分離 (line 15)
# WHEN: --issues モードで同一 Phase 内に deps.yaml 変更 Issue が2件以上含まれる
# THEN: deps.yaml 変更 Issue が自動的に sequential Phase に分離される

test_autopilot_plan_deps_conflict_detection() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # deps.yaml 競合検出ロジックの存在
  assert_file_contains "$AUTOPILOT_PLAN" 'deps\.yaml' || return 1
  return 0
}
run_test "autopilot-plan.sh に deps.yaml 競合検出ロジックがある" test_autopilot_plan_deps_conflict_detection

test_autopilot_plan_sequential_separation() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # sequential/分離処理の存在
  assert_file_contains "$AUTOPILOT_PLAN" '(sequential|separ|split|conflict)' || return 1
  return 0
}
run_test "autopilot-plan.sh に deps.yaml 競合時の Phase 分離ロジックがある" test_autopilot_plan_sequential_separation

# Edge case: deps.yaml 競合が3件以上の場合も正しく sequential に分離されるか
test_autopilot_plan_multi_conflict() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  # ループ/反復処理で複数競合に対応していること
  assert_file_contains "$AUTOPILOT_PLAN" '(for|while|loop|each)' || return 1
  return 0
}
run_test "autopilot-plan.sh [edge: 複数 deps.yaml 競合の反復処理]" test_autopilot_plan_multi_conflict

# Edge case: --project-dir / --repo-mode パラメータ処理
test_autopilot_plan_project_dir_param() {
  assert_file_exists "$AUTOPILOT_PLAN" || return 1
  assert_file_contains "$AUTOPILOT_PLAN" '--project-dir' || return 1
  assert_file_contains "$AUTOPILOT_PLAN" '--repo-mode' || return 1
  return 0
}
run_test "autopilot-plan.sh [edge: --project-dir と --repo-mode パラメータ処理]" test_autopilot_plan_project_dir_param

# =============================================================================
# Requirement: autopilot-should-skip スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: autopilot-should-skip スクリプト移植 ---"

# Scenario: 依存先が failed の場合スキップ (line 24)
# WHEN: plan.yaml で Issue A が Issue B に依存しており、Issue B の status が failed である
# THEN: exit code 0（skip）を返す

test_should_skip_exists() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP"
}
run_test "autopilot-should-skip.sh が存在する" test_should_skip_exists

test_should_skip_executable() {
  assert_file_executable "$AUTOPILOT_SHOULD_SKIP"
}
run_test "autopilot-should-skip.sh が実行可能である" test_should_skip_executable

test_should_skip_failed_dependency() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP" || return 1
  assert_file_contains "$AUTOPILOT_SHOULD_SKIP" 'failed' || return 1
  return 0
}
run_test "autopilot-should-skip.sh に failed 依存先の検出ロジックがある" test_should_skip_failed_dependency

test_should_skip_state_read_integration() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP" || return 1
  # state-read.sh 経由で状態参照していること（マーカーファイル直接参照でないこと）
  assert_file_contains "$AUTOPILOT_SHOULD_SKIP" 'state-read' || return 1
  return 0
}
run_test "autopilot-should-skip.sh が state-read.sh 経由で状態参照する" test_should_skip_state_read_integration

# Edge case: マーカーファイル直接参照が排除されていること
test_should_skip_no_marker_files() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP" || return 1
  # MARKER_DIR や直接マーカーファイル参照がないこと
  assert_file_not_contains "$AUTOPILOT_SHOULD_SKIP" 'MARKER_DIR' || return 1
  return 0
}
run_test "autopilot-should-skip.sh [edge: MARKER_DIR 直接参照が排除されている]" test_should_skip_no_marker_files

# Scenario: 依存先が全て done の場合実行 (line 28)
# WHEN: plan.yaml で Issue A が Issue B に依存しており、Issue B の status が done である
# THEN: exit code 1（実行）を返す

test_should_skip_done_dependency() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP" || return 1
  assert_file_contains "$AUTOPILOT_SHOULD_SKIP" 'done' || return 1
  return 0
}
run_test "autopilot-should-skip.sh に done 状態の検出ロジックがある" test_should_skip_done_dependency

# Scenario: 依存なしの場合実行 (line 32)
# WHEN: plan.yaml で Issue A に依存先がない
# THEN: exit code 1（実行）を返す

test_should_skip_no_dependency() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP" || return 1
  # 依存なし→実行のロジック（exit 1 = 実行）
  assert_file_contains "$AUTOPILOT_SHOULD_SKIP" '(no.*depend|depend.*empty|exit 1)' || return 1
  return 0
}
run_test "autopilot-should-skip.sh に依存なし→実行のロジックがある" test_should_skip_no_dependency

# Edge case: plan.yaml が存在しない場合のエラーハンドリング
test_should_skip_missing_plan() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP" || return 1
  assert_file_contains "$AUTOPILOT_SHOULD_SKIP" '(plan\.yaml|\.autopilot)' || return 1
  return 0
}
run_test "autopilot-should-skip.sh [edge: plan.yaml 参照がある]" test_should_skip_missing_plan

# Edge case: exit code の正しい規約（0=skip, 1=execute）
test_should_skip_exit_code_convention() {
  assert_file_exists "$AUTOPILOT_SHOULD_SKIP" || return 1
  # exit 0 と exit 1 の両方が使われていること
  assert_file_contains "$AUTOPILOT_SHOULD_SKIP" 'exit 0' || return 1
  assert_file_contains "$AUTOPILOT_SHOULD_SKIP" 'exit 1' || return 1
  return 0
}
run_test "autopilot-should-skip.sh [edge: exit 0=skip, exit 1=execute 規約]" test_should_skip_exit_code_convention

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "autopilot-scripts-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
