#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: worktree-branch-scripts.md
# Generated from: deltaspec/changes/c-4-scripts-migration/specs/worktree-branch-scripts.md
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

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
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

WORKTREE_CREATE="scripts/worktree-create.sh"
BRANCH_CREATE="scripts/branch-create.sh"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: worktree-create スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: worktree-create スクリプト移植 ---"

# Scenario: Issue番号指定での worktree 作成 (line 8)
# WHEN: bash scripts/worktree-create.sh '#11' を実行する
# THEN: Issue タイトルとラベルから slug を生成し、worktrees/<branch>/ に worktree が作成される

test_worktree_create_exists() {
  assert_file_exists "$WORKTREE_CREATE"
}
run_test "worktree-create.sh が存在する" test_worktree_create_exists

test_worktree_create_executable() {
  assert_file_executable "$WORKTREE_CREATE"
}
run_test "worktree-create.sh が実行可能である" test_worktree_create_executable

test_worktree_create_issue_parsing() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  # Issue 番号パースロジック
  assert_file_contains "$WORKTREE_CREATE" '(issue|#[0-9]|\$1)' || return 1
  return 0
}
run_test "worktree-create.sh に Issue 番号パースロジックがある" test_worktree_create_issue_parsing

test_worktree_create_slug_generation() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  # slug 生成ロジック（Issue タイトルからブランチ名生成）
  assert_file_contains "$WORKTREE_CREATE" '(slug|title|branch.*name|sanitize)' || return 1
  return 0
}
run_test "worktree-create.sh に slug 生成ロジックがある" test_worktree_create_slug_generation

test_worktree_create_git_worktree_add() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  # git --git-dir=... worktree add 形式で呼び出し
  assert_file_contains "$WORKTREE_CREATE" 'worktree add' || return 1
  return 0
}
run_test "worktree-create.sh に git worktree add 呼び出しがある" test_worktree_create_git_worktree_add

# Edge case: 固定パス参照の排除
test_worktree_create_no_hardcoded_path() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  # $HOME/.claude/plugins/dev/scripts/ への固定パス参照がないこと
  assert_file_not_contains "$WORKTREE_CREATE" '\$HOME/\.claude/plugins/dev/scripts' || return 1
  assert_file_not_contains "$WORKTREE_CREATE" '~/\.claude/plugins/dev/scripts' || return 1
  return 0
}
run_test "worktree-create.sh [edge: 旧固定パス参照が排除されている]" test_worktree_create_no_hardcoded_path

# Edge case: worktrees/ ディレクトリへの作成
test_worktree_create_worktrees_dir() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  assert_file_contains "$WORKTREE_CREATE" 'worktrees/' || return 1
  return 0
}
run_test "worktree-create.sh [edge: worktrees/ ディレクトリに作成する]" test_worktree_create_worktrees_dir

# Scenario: ブランチ名バリデーション (line 12)
# WHEN: 不正なブランチ名（大文字、50文字超、予約語）が指定される
# THEN: エラーメッセージと修正候補が表示される

test_worktree_create_branch_validation() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  # ブランチ名バリデーション処理
  assert_file_contains "$WORKTREE_CREATE" '(valid|length|char|pattern|50)' || return 1
  return 0
}
run_test "worktree-create.sh にブランチ名バリデーションがある" test_worktree_create_branch_validation

# Edge case: 大文字→小文字変換
test_worktree_create_lowercase() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  assert_file_contains "$WORKTREE_CREATE" '(lower|tr.*A-Z.*a-z|,,)' || return 1
  return 0
}
run_test "worktree-create.sh [edge: 大文字→小文字変換処理]" test_worktree_create_lowercase

# Edge case: 50文字超のブランチ名切り詰め
test_worktree_create_length_limit() {
  assert_file_exists "$WORKTREE_CREATE" || return 1
  assert_file_contains "$WORKTREE_CREATE" '(50|length|truncat|cut|substr)' || return 1
  return 0
}
run_test "worktree-create.sh [edge: ブランチ名長さ制限処理]" test_worktree_create_length_limit

# =============================================================================
# Requirement: branch-create スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: branch-create スクリプト移植 ---"

# Scenario: Issue番号指定でのブランチ作成 (line 20)
# WHEN: bash scripts/branch-create.sh '#11' を実行する
# THEN: Issue タイトルとラベルから slug を生成し、feature ブランチが作成される

test_branch_create_exists() {
  assert_file_exists "$BRANCH_CREATE"
}
run_test "branch-create.sh が存在する" test_branch_create_exists

test_branch_create_executable() {
  assert_file_executable "$BRANCH_CREATE"
}
run_test "branch-create.sh が実行可能である" test_branch_create_executable

test_branch_create_issue_parsing() {
  assert_file_exists "$BRANCH_CREATE" || return 1
  assert_file_contains "$BRANCH_CREATE" '(issue|#[0-9]|\$1)' || return 1
  return 0
}
run_test "branch-create.sh に Issue 番号パースロジックがある" test_branch_create_issue_parsing

test_branch_create_git_branch() {
  assert_file_exists "$BRANCH_CREATE" || return 1
  assert_file_contains "$BRANCH_CREATE" '(git checkout -b|git branch|git switch -c)' || return 1
  return 0
}
run_test "branch-create.sh に git ブランチ作成呼び出しがある" test_branch_create_git_branch

# Edge case: 通常 repo 向け（worktree ではない）
test_branch_create_no_worktree() {
  assert_file_exists "$BRANCH_CREATE" || return 1
  # worktree-create.sh とは異なり、git worktree add は使わない
  assert_file_not_contains "$BRANCH_CREATE" 'git worktree add' || return 1
  return 0
}
run_test "branch-create.sh [edge: git worktree add を使わない]" test_branch_create_no_worktree

# Scenario: --auto --auto-merge フラグの引き継ぎ (line 24)
# WHEN: bash scripts/branch-create.sh --auto --auto-merge '#11' を実行する
# THEN: ブランチ作成後、フラグ情報が stdout に出力される

# --auto / --auto-merge フラグは設計変更により branch-create.sh から除外済み
# autopilot フローは worktree-create.sh + co-autopilot スキルが担当
run_test_skip "branch-create.sh に --auto フラグ処理がある" "設計変更: autopilot フローは co-autopilot が担当"
run_test_skip "branch-create.sh に --auto-merge フラグ処理がある" "設計変更: autopilot フローは co-autopilot が担当"

# Edge case: ブランチ作成結果の stdout 出力
test_branch_create_result_output() {
  assert_file_exists "$BRANCH_CREATE" || return 1
  # 作成結果を出力するロジック
  assert_file_contains "$BRANCH_CREATE" '(echo.*ブランチ|echo.*完了|BRANCH_NAME)' || return 1
  return 0
}
run_test "branch-create.sh [edge: 作成結果を stdout に出力する]" test_branch_create_result_output

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "worktree-branch-scripts-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
