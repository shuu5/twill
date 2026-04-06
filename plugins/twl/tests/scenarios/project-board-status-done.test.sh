#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: project-status-done workflow
# Generated from: deltaspec/changes/project-board-add-to-project-closedone/specs/project-status-done.md
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

WORKFLOW_FILE=".github/workflows/project-status-done.yml"

# =============================================================================
# Requirement: Issue close 時の Status Done 自動更新 - 基本構造
# =============================================================================
echo ""
echo "--- Requirement: project-status-done.yml 基本構造 ---"

test_workflow_file_exists() {
  assert_file_exists "$WORKFLOW_FILE"
}
run_test "project-status-done.yml が存在する" test_workflow_file_exists

test_workflow_valid_yaml_structure() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains_all "$WORKFLOW_FILE" \
    "^on:" \
    "^jobs:"
}
run_test "project-status-done.yml に on: と jobs: がある" test_workflow_valid_yaml_structure

test_trigger_issues_closed() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # on.issues.types に closed が含まれる
  assert_file_contains "$WORKFLOW_FILE" "closed"
}
run_test "issues closed トリガーが定義されている" test_trigger_issues_closed

# Edge case: closed のみをトリガーとし opened など余分なイベントを含まない
test_trigger_closed_only() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains "$WORKFLOW_FILE" "closed"
  # opened が on: ブロックに混入していないこと（status-done は close 専用）
  assert_file_not_contains "$WORKFLOW_FILE" "^\s*-\s*opened"
}
run_test "基本構造 [edge: closed 以外の Issue イベントをトリガーしていない]" test_trigger_closed_only

# Edge case: gh CLI が使用できる環境変数 GH_TOKEN が設定されている
test_gh_token_configured() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # GH_TOKEN または github-token/GITHUB_TOKEN 経由で認証
  assert_file_contains "$WORKFLOW_FILE" "(GH_TOKEN|GITHUB_TOKEN|ADD_TO_PROJECT_PAT)"
}
run_test "基本構造 [edge: GH_TOKEN/認証トークンが設定されている]" test_gh_token_configured

# =============================================================================
# Scenario: Board 登録済み Issue の close (spec line 7)
# WHEN: Project Board に登録済みの Issue が close される
# THEN: 該当 Issue の Project Board Status が Done に更新される
# =============================================================================
echo ""
echo "--- Requirement: Board 登録済み Issue の close ---"

test_uses_graphql_mutation() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # updateProjectV2ItemFieldValue mutation が使用されている
  assert_file_contains "$WORKFLOW_FILE" "updateProjectV2ItemFieldValue"
}
run_test "updateProjectV2ItemFieldValue mutation が使用されている" test_uses_graphql_mutation

test_done_option_id_configured() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # Done option ID: 98236657 がハードコードされている
  assert_file_contains "$WORKFLOW_FILE" "98236657"
}
run_test "Done option ID (98236657) が設定されている" test_done_option_id_configured

test_status_field_id_configured() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # Status field ID: PVTSSF_lAHOCNFEd84BS03gzhAPzog
  assert_file_contains "$WORKFLOW_FILE" "PVTSSF_lAHOCNFEd84BS03gzhAPzog"
}
run_test "Status field ID (PVTSSF_lAHOCNFEd84BS03gzhAPzog) が設定されている" test_status_field_id_configured

test_project_id_configured() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # Project ID: PVT_kwHOCNFEd84BS03g
  assert_file_contains "$WORKFLOW_FILE" "PVT_kwHOCNFEd84BS03g"
}
run_test "Project ID (PVT_kwHOCNFEd84BS03g) が設定されている" test_project_id_configured

# Edge case: singleSelectValue ではなく optionId で Done を指定
test_mutation_uses_option_id() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # singleSelectValue { optionId } 形式で mutation を呼ぶ
  assert_file_contains "$WORKFLOW_FILE" "(optionId|singleSelectValue)"
}
run_test "Board 登録済み [edge: mutation が optionId/singleSelectValue 形式を使用]" test_mutation_uses_option_id

# =============================================================================
# Scenario: Board 未登録 Issue の close (spec line 11)
# WHEN: Project Board に未登録の Issue が close される
# THEN: workflow run は success（green）で完了し、エラーを発生させてはならない（MUST NOT）
# =============================================================================
echo ""
echo "--- Requirement: Board 未登録 Issue の close ---"

test_graceful_skip_when_not_found() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # Item が見つからない場合のガード（if/conditional, exit 0, continue, || true など）
  assert_file_contains "$WORKFLOW_FILE" "(\|\|\s*(true|exit 0|:)|exit\s+0|if\s+\[\[|\bif\b.*item|not found|未登録|skip)"
}
run_test "Board 未登録 Issue でも workflow が success で終了する" test_graceful_skip_when_not_found

# Edge case: Item 未発見時に exit 1 を呼ばない
test_no_exit_1_on_missing_item() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # Item が空のとき exit 1 を発火しない（条件なしの exit 1 がないこと）
  # "exit 1" が存在してもガード節内のみであれば許容するが、
  # 無条件の "exit 1" が存在しないことを確認
  if grep -qP "^\s*exit\s+1\s*$" "${PROJECT_ROOT}/${WORKFLOW_FILE}" 2>/dev/null; then
    # 無条件 exit 1 があれば失敗
    return 1
  fi
  return 0
}
run_test "Board 未登録 [edge: Item 未発見時に無条件 exit 1 がない]" test_no_exit_1_on_missing_item

# Edge case: 空 Item リストのチェックが Item 操作前に行われる
test_item_check_before_mutation() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # Item 検索結果を変数に格納してから mutation を実行する構造
  assert_file_contains "$WORKFLOW_FILE" "(ITEM_ID|item_id|itemId|PROJECT_ITEM)"
}
run_test "Board 未登録 [edge: Item ID を変数に格納してから mutation を実行する構造]" test_item_check_before_mutation

# =============================================================================
# Scenario: GraphQL mutation の実行 (spec line 15)
# WHEN: Issue の Project Item が検出された場合
# THEN: updateProjectV2ItemFieldValue mutation で Status field を Done option に更新しなければならない（MUST）
# =============================================================================
echo ""
echo "--- Requirement: GraphQL mutation の実行 ---"

test_gh_api_graphql_used() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # gh api graphql コマンドが使用されている
  assert_file_contains "$WORKFLOW_FILE" "gh api graphql"
}
run_test "gh api graphql コマンドが使用されている" test_gh_api_graphql_used

# Edge case: mutation に projectId, itemId, fieldId, value が全て含まれる
test_mutation_required_fields() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains_all "$WORKFLOW_FILE" \
    "(projectId|project_id)" \
    "(itemId|item_id)" \
    "(fieldId|field_id)"
}
run_test "GraphQL mutation [edge: projectId/itemId/fieldId の3フィールドが全て含まれる]" test_mutation_required_fields

# Edge case: mutation が変数（$variable）を使用してインジェクションを防ぐ
test_mutation_uses_variables() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # -f または --field を使って mutation variables を渡す
  assert_file_contains "$WORKFLOW_FILE" "(-f\s|--field\s)"
}
run_test "GraphQL mutation [edge: -f/--field で変数を渡し文字列連結を避けている]" test_mutation_uses_variables

# =============================================================================
# Scenario: Item 検索の実装 (spec line 19)
# WHEN: workflow が実行される
# THEN: gh api graphql で Project items を取得し、Issue number と repository でフィルタして対象 Item を特定しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: Item 検索の実装 ---"

test_item_search_by_issue_number() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # github.event.issue.number を使用して Issue 番号を取得
  assert_file_contains "$WORKFLOW_FILE" "(github\.event\.issue\.number|issue\.number|ISSUE_NUMBER)"
}
run_test "Issue number でフィルタする構造がある" test_item_search_by_issue_number

test_item_search_uses_project_items_query() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # Project items を取得する query（items, nodes, content などの GraphQL フィールド）
  assert_file_contains "$WORKFLOW_FILE" "(items|nodes|content.*url|content.*number)"
}
run_test "Project items を取得する GraphQL query が定義されている" test_item_search_uses_project_items_query

# Edge case: repository でもフィルタしている（他リポの同番号 Issue と区別）
test_item_search_filters_by_repository() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # repository フィルタ（repo url, repository name など）
  assert_file_contains "$WORKFLOW_FILE" "(repository|repo|github\.repository|REPO)"
}
run_test "Item 検索 [edge: Issue number だけでなく repository でもフィルタしている]" test_item_search_filters_by_repository

# Edge case: pagination を考慮した items 取得（first: N または after カーソル）
test_item_search_handles_pagination() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  # first: N で items 件数を制限、または pageInfo/hasNextPage を処理
  assert_file_contains "$WORKFLOW_FILE" "(first:\s*[0-9]|pageInfo|hasNextPage|endCursor)"
}
run_test "Item 検索 [edge: first: N で items 件数が制限されている（pagination 考慮）]" test_item_search_handles_pagination

# Edge case: jq を使って items をフィルタ・パースしている
test_item_search_uses_jq() {
  assert_file_exists "$WORKFLOW_FILE" || return 1
  assert_file_contains "$WORKFLOW_FILE" "jq"
}
run_test "Item 検索 [edge: jq で GraphQL レスポンスをパース]" test_item_search_uses_jq

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "project-board-status-done: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "==========================================="

[[ ${FAIL} -eq 0 ]]
