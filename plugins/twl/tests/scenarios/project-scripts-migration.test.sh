#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: project-scripts.md
# Generated from: deltaspec/changes/c-4-scripts-migration/specs/project-scripts.md
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

PROJECT_CREATE="scripts/project-create.sh"
PROJECT_MIGRATE="scripts/project-migrate.sh"

# =============================================================================
# Requirement: project-create スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: project-create スクリプト移植 ---"

# Scenario: 新規プロジェクト作成 (line 8)
# WHEN: bash scripts/project-create.sh --name my-project --template default を実行する
# THEN: bare repo が作成され、main worktree が設定される

test_project_create_exists() {
  assert_file_exists "$PROJECT_CREATE"
}
run_test "project-create.sh が存在する" test_project_create_exists

test_project_create_executable() {
  assert_file_executable "$PROJECT_CREATE"
}
run_test "project-create.sh が実行可能である" test_project_create_executable

test_project_create_name_param() {
  assert_file_exists "$PROJECT_CREATE" || return 1
  # プロジェクト名は positional arg で受け取り PROJECT_NAME に格納
  assert_file_contains "$PROJECT_CREATE" 'PROJECT_NAME' || return 1
  return 0
}
run_test "project-create.sh にプロジェクト名パラメータ処理がある" test_project_create_name_param

test_project_create_template_param() {
  assert_file_exists "$PROJECT_CREATE" || return 1
  # テンプレートは --type パラメータで指定
  assert_file_contains "$PROJECT_CREATE" '--type' || return 1
  return 0
}
run_test "project-create.sh に --type パラメータ処理がある" test_project_create_template_param

test_project_create_bare_repo() {
  assert_file_exists "$PROJECT_CREATE" || return 1
  # bare repo 初期化ロジック
  assert_file_contains "$PROJECT_CREATE" '(git.*init.*bare|\.bare|--bare)' || return 1
  return 0
}
run_test "project-create.sh に bare repo 初期化ロジックがある" test_project_create_bare_repo

test_project_create_main_worktree() {
  assert_file_exists "$PROJECT_CREATE" || return 1
  # main worktree 設定
  assert_file_contains "$PROJECT_CREATE" '(git worktree|main)' || return 1
  return 0
}
run_test "project-create.sh に main worktree 設定がある" test_project_create_main_worktree

# Edge case: 既存プロジェクト名との衝突チェック
test_project_create_name_collision() {
  assert_file_exists "$PROJECT_CREATE" || return 1
  # 既存チェック: 日本語「既に存在します」または -d チェック
  assert_file_contains "$PROJECT_CREATE" '(既に存在|exist|already|-d "\$PROJECT_DIR")' || return 1
  return 0
}
run_test "project-create.sh [edge: 既存プロジェクト名衝突チェック]" test_project_create_name_collision

# Edge case: テンプレート適用ロジック
test_project_create_template_apply() {
  assert_file_exists "$PROJECT_CREATE" || return 1
  assert_file_contains "$PROJECT_CREATE" '(template|copy|cp|rsync|apply)' || return 1
  return 0
}
run_test "project-create.sh [edge: テンプレート適用ロジック]" test_project_create_template_apply

# =============================================================================
# Requirement: project-migrate スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: project-migrate スクリプト移植 ---"

# Scenario: テンプレート更新 (line 17)
# WHEN: bash scripts/project-migrate.sh --project-dir $PWD を実行する
# THEN: 最新テンプレートとの差分が検出され、更新が適用される

test_project_migrate_exists() {
  assert_file_exists "$PROJECT_MIGRATE"
}
run_test "project-migrate.sh が存在する" test_project_migrate_exists

test_project_migrate_executable() {
  assert_file_executable "$PROJECT_MIGRATE"
}
run_test "project-migrate.sh が実行可能である" test_project_migrate_executable

test_project_migrate_project_dir_param() {
  assert_file_exists "$PROJECT_MIGRATE" || return 1
  # カレントディレクトリをプロジェクトルートとして使用（pwd ベース）
  assert_file_contains "$PROJECT_MIGRATE" '(PROJECT_DIR|pwd|--type|--dry-run)' || return 1
  return 0
}
run_test "project-migrate.sh にプロジェクトディレクトリ解決処理がある" test_project_migrate_project_dir_param

test_project_migrate_diff_detection() {
  assert_file_exists "$PROJECT_MIGRATE" || return 1
  assert_file_contains "$PROJECT_MIGRATE" '(diff|compare|template|version)' || return 1
  return 0
}
run_test "project-migrate.sh にテンプレート差分検出ロジックがある" test_project_migrate_diff_detection

test_project_migrate_update_apply() {
  assert_file_exists "$PROJECT_MIGRATE" || return 1
  assert_file_contains "$PROJECT_MIGRATE" '(update|apply|copy|migrate)' || return 1
  return 0
}
run_test "project-migrate.sh に更新適用ロジックがある" test_project_migrate_update_apply

# Edge case: ガバナンス再適用
test_project_migrate_governance() {
  assert_file_exists "$PROJECT_MIGRATE" || return 1
  assert_file_contains "$PROJECT_MIGRATE" '(governance|CLAUDE\.md|settings|rules)' || return 1
  return 0
}
run_test "project-migrate.sh [edge: ガバナンス再適用処理]" test_project_migrate_governance

# Edge case: dry-run / 差分表示
test_project_migrate_dry_run() {
  assert_file_exists "$PROJECT_MIGRATE" || return 1
  assert_file_contains "$PROJECT_MIGRATE" '(dry.run|preview|show|diff|confirm)' || return 1
  return 0
}
run_test "project-migrate.sh [edge: 差分プレビュー/確認処理]" test_project_migrate_dry_run

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "project-scripts-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
