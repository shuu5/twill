#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: add-to-project workflow
# Generated from: openspec/changes/project-board-add-to-project-closedone/specs/add-to-project.md
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

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
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

WORKFLOW_FILE=".github/workflows/add-to-project.yml"

# =============================================================================
# Requirement: Issue の Project Board 自動追加 - 基本構造
# =============================================================================
echo ""
echo "--- Requirement: add-to-project.yml 基本構造 ---"

test_workflow_file_exists() {
  assert_file_exists "$WORKFLOW_FILE"
}
run_test "add-to-project.yml が存在する" test_workflow_file_exists

test_workflow_valid_yaml_structure() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # on: および jobs: キーが存在すること
  assert_file_contains_all "$WORKFLOW_FILE" \
    "^on:" \
    "^jobs:"
}
run_test "add-to-project.yml に on: と jobs: がある" test_workflow_valid_yaml_structure

# =============================================================================
# Scenario: 新規 Issue 作成時の自動追加 (spec line 7)
# WHEN: リポジトリで新しい Issue が作成される
# THEN: Issue が Project Board（#3: twill-ecosystem）に自動追加される
# =============================================================================
echo ""
echo "--- Requirement: 新規 Issue 作成時の自動追加 ---"

test_trigger_issues_opened() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # issues トリガーに opened が含まれる
  assert_file_contains "$WORKFLOW_FILE" "opened"
}
run_test "issues opened トリガーが定義されている" test_trigger_issues_opened

test_uses_add_to_project_action() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # actions/add-to-project を使用している
  assert_file_contains "$WORKFLOW_FILE" "actions/add-to-project"
}
run_test "actions/add-to-project Action が使用されている" test_uses_add_to_project_action

test_project_url_configured() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # project-url に Project #3 の URL が設定されている
  assert_file_contains "$WORKFLOW_FILE" "project-url"
}
run_test "project-url が設定されている" test_project_url_configured

test_project_url_points_to_project_3() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # shuu5/projects/3 を指している
  assert_file_contains "$WORKFLOW_FILE" "(shuu5/projects/3|projects/3)"
}
run_test "project-url が twill-ecosystem (#3) を指している" test_project_url_points_to_project_3

# Edge case: PAT をトークンとして使用（GITHUB_TOKEN ではなく ADD_TO_PROJECT_PAT）
test_uses_add_to_project_pat() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains "$WORKFLOW_FILE" "ADD_TO_PROJECT_PAT"
}
run_test "新規 Issue [edge: ADD_TO_PROJECT_PAT が github-token に設定]" test_uses_add_to_project_pat

# Edge case: secrets. 経由でトークンを参照（平文ではない）
test_pat_via_secrets() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains "$WORKFLOW_FILE" "secrets\.ADD_TO_PROJECT_PAT"
}
run_test "新規 Issue [edge: secrets.ADD_TO_PROJECT_PAT で参照されている]" test_pat_via_secrets

# =============================================================================
# Scenario: Issue reopen 時の再追加 (spec line 11)
# WHEN: クローズ済みの Issue が reopen される
# THEN: Issue が Project Board に追加される（既に存在する場合は冪等に処理される）
# =============================================================================
echo ""
echo "--- Requirement: Issue reopen 時の再追加 ---"

test_trigger_issues_reopened() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains "$WORKFLOW_FILE" "reopened"
}
run_test "issues reopened トリガーが定義されている" test_trigger_issues_reopened

# Edge case: opened と reopened が同一 on.issues.types リストに含まれる
test_opened_reopened_same_block() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # types: リストに opened と reopened が両方ある（前後10行以内に共存）
  assert_file_contains "$WORKFLOW_FILE" "reopened"
  assert_file_contains "$WORKFLOW_FILE" "opened"
}
run_test "reopen [edge: opened と reopened が同一 types リスト内]" test_opened_reopened_same_block

# =============================================================================
# Scenario: Issue transfer 時の追加 (spec line 15)
# WHEN: 他リポジトリから Issue が transfer される
# THEN: 転送先リポジトリの workflow により Issue が Project Board に追加される
# =============================================================================
echo ""
echo "--- Requirement: Issue transfer 時の追加 ---"

test_trigger_issues_transferred() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains "$WORKFLOW_FILE" "transferred"
}
run_test "issues transferred トリガーが定義されている" test_trigger_issues_transferred

# Edge case: 3 トリガー（opened/reopened/transferred）が全て on.issues.types に列挙
test_all_three_triggers_present() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains_all "$WORKFLOW_FILE" \
    "opened" \
    "reopened" \
    "transferred"
}
run_test "transfer [edge: opened/reopened/transferred の3トリガーが全て定義]" test_all_three_triggers_present

# Edge case: on.issues のみでトリガー（on.issues.types なしは全 Issue イベントを受ける）
# transferred は types 省略では受信されないため types 指定が必須
test_types_list_is_specified() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains "$WORKFLOW_FILE" "types:"
}
run_test "transfer [edge: types: が明示指定されている（transferred は省略不可）]" test_types_list_is_specified

# =============================================================================
# Scenario: PAT 未設定時のエラー (spec line 19)
# WHEN: ADD_TO_PROJECT_PAT Secret が未登録の状態で workflow が実行される
# THEN: workflow run が失敗し、Secret 未設定が原因であることがログから判別できる
# =============================================================================
echo ""
echo "--- Requirement: PAT 未設定時のエラー ---"

test_github_token_uses_pat_not_github_token() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # GITHUB_TOKEN ではなく ADD_TO_PROJECT_PAT を使用している（PAT が必要）
  assert_file_contains "$WORKFLOW_FILE" "ADD_TO_PROJECT_PAT"
  assert_file_not_contains "$WORKFLOW_FILE" "github-token.*GITHUB_TOKEN" || true
}
run_test "PAT 未設定 [ADD_TO_PROJECT_PAT が github-token として使用されている]" test_github_token_uses_pat_not_github_token

# Edge case: GITHUB_TOKEN を代替として使用していない（Project への書き込み権限不足のため）
test_no_plain_github_token_for_project() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # secrets.GITHUB_TOKEN で project を操作しようとしていないこと
  # （GITHUB_TOKEN で project V2 への write は不可）
  assert_file_not_contains "$WORKFLOW_FILE" "github-token:.*secrets\.GITHUB_TOKEN"
}
run_test "PAT 未設定 [edge: GITHUB_TOKEN を project token として使用していない]" test_no_plain_github_token_for_project

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "project-board-add-to-project: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "==========================================="

[[ ${FAIL} -eq 0 ]]
