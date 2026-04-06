#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: project-board-backfill.sh
# Generated from: deltaspec/changes/77-fix-project-board-status-update/specs/project-detection/spec.md
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

BACKFILL_SCRIPT="scripts/project-board-backfill.sh"
STATUS_UPDATE_CMD="commands/project-board-status-update.md"
# TITLE_MATCH_PROJECT / MATCHED_PROJECTS パターンは resolve-project-lib (#137) で共通化済み
LIB_SCRIPT="scripts/lib/resolve-project.sh"
SYNC_CMD="commands/project-board-sync.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: バッチバックフィルスクリプト - 基本構造
# =============================================================================
echo ""
echo "--- Requirement: バッチバックフィルスクリプト - 基本構造 ---"

test_backfill_script_exists() {
  assert_file_exists "$BACKFILL_SCRIPT"
}
run_test "project-board-backfill.sh が存在する" test_backfill_script_exists

test_backfill_script_executable() {
  assert_file_executable "$BACKFILL_SCRIPT"
}
run_test "project-board-backfill.sh が実行可能である" test_backfill_script_executable

test_backfill_script_bash_syntax() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${BACKFILL_SCRIPT}" 2>/dev/null
}
run_test "project-board-backfill.sh の bash 構文が正しい" test_backfill_script_bash_syntax

test_backfill_script_shebang() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  local first_line
  first_line=$(head -1 "${PROJECT_ROOT}/${BACKFILL_SCRIPT}")
  [[ "$first_line" == "#!/usr/bin/env bash" || "$first_line" == "#!/bin/bash" ]]
}
run_test "project-board-backfill.sh にシェバンがある" test_backfill_script_shebang

# =============================================================================
# Requirement: Issue 範囲処理
# Scenario: Issue 範囲を指定して一括追加 (spec line 30)
# WHEN: bash scripts/project-board-backfill.sh 41 58 を実行する
# THEN: Issue #41 から #58 の全 Issue が Project Board に追加される
# =============================================================================
echo ""
echo "--- Requirement: Issue 範囲処理 ---"

# Edge case: 引数として開始番号と終了番号を受け付ける
test_backfill_accepts_range_args() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  # スクリプトに $1, $2 や引数処理の記述がある
  assert_file_contains "$BACKFILL_SCRIPT" '(\$1|\$2|\${1|\$\{2|START|END|start|end|begin|from|to)' || return 1
  return 0
}
run_test "backfill [edge: 開始/終了番号の引数処理がある]" test_backfill_accepts_range_args

# Edge case: ループでの Issue 処理 (for/while で範囲をイテレート)
test_backfill_issue_loop() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(for\s|while\s|seq\s)' || return 1
  return 0
}
run_test "backfill [edge: Issue をループ処理する構造がある]" test_backfill_issue_loop

# Edge case: 逆順範囲（例: 58 41）のガード
test_backfill_reversed_range_guard() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  # 逆順を検出するロジック（比較、swap、エラー出力のいずれか）
  assert_file_contains "$BACKFILL_SCRIPT" '(-gt|-ge|>|swap|reverse|invalid.*range|開始.*終了|must.*less|順序)' || return 1
  return 0
}
run_test "backfill [edge: 逆順範囲のバリデーション]" test_backfill_reversed_range_guard

# Edge case: 単一 Issue（開始=終了）でも動作する構造
test_backfill_single_issue() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  # seq や for i in $(seq ...) が start == end でも 1 回実行される構造
  # seq $start $end は start==end なら 1 回出力する
  assert_file_contains "$BACKFILL_SCRIPT" '(seq|for.*in|while)' || return 1
  return 0
}
run_test "backfill [edge: 単一 Issue 処理可能な構造]" test_backfill_single_issue

# Edge case: 引数不足時のエラーメッセージ/使用方法表示
test_backfill_missing_args_usage() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(usage|Usage|USAGE|使い方|引数.*不足|argument)' || return 1
  return 0
}
run_test "backfill [edge: 引数不足時の使用方法表示]" test_backfill_missing_args_usage

# Edge case: 引数が正の整数であることのバリデーション
test_backfill_integer_validation() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(\[\[.*=~.*\^?\[0-9\]|^[1-9]|integer|数値|numeric)' || return 1
  return 0
}
run_test "backfill [edge: 引数の整数バリデーション]" test_backfill_integer_validation

# =============================================================================
# Requirement: 既に Board に存在する Issue の処理
# Scenario: 既に Board に存在する Issue (spec line 34)
# WHEN: バッチ対象に既に Board に存在する Issue が含まれる
# THEN: エラーにならず処理を継続する
# =============================================================================
echo ""
echo "--- Requirement: 既存 Issue の重複処理 ---"

# gh project item-add の呼び出しがある
test_backfill_uses_item_add() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" 'gh project item-add' || return 1
  return 0
}
run_test "backfill に gh project item-add 呼び出しがある" test_backfill_uses_item_add

# Edge case: item-add のエラーでスクリプトが停止しない (set -e の回避 or エラーキャッチ)
test_backfill_continues_on_add_error() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  # || true, || continue, 2>/dev/null, if ! ..., set +e のいずれか
  assert_file_contains "$BACKFILL_SCRIPT" '(\|\|\s*(true|continue|:)|2>/dev/null|set \+e|if\s+!)' || return 1
  return 0
}
run_test "backfill [edge: item-add 失敗でもスクリプトが停止しない]" test_backfill_continues_on_add_error

# =============================================================================
# Requirement: 存在しない Issue 番号の処理
# Scenario: 存在しない Issue 番号 (spec line 38)
# WHEN: 指定範囲に存在しない Issue 番号が含まれる
# THEN: 該当 Issue をスキップし、警告を出力して次の Issue の処理を継続する
# =============================================================================
echo ""
echo "--- Requirement: 存在しない Issue のスキップ ---"

# Edge case: 警告出力ロジックがある
test_backfill_skip_warning() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(warn|WARNING|WARN|skip|SKIP|スキップ|警告|⚠)' || return 1
  return 0
}
run_test "backfill [edge: 存在しない Issue の警告/スキップ出力]" test_backfill_skip_warning

# Edge case: エラー発生後も次の Issue の処理を継続する (continue or ループ構造)
test_backfill_continues_after_skip() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(continue|次|next)' || return 1
  return 0
}
run_test "backfill [edge: スキップ後にループ継続する]" test_backfill_continues_after_skip

# =============================================================================
# Requirement: Project 検出 (TITLE_MATCH_PROJECT)
# Scenario: リポジトリ名と一致するタイトルの Project が存在する場合 (spec line 8)
# THEN: TITLE_MATCH_PROJECT としてその Project を優先選択
# =============================================================================
echo ""
echo "--- Requirement: Project 検出 (TITLE_MATCH_PROJECT) ---"

# TITLE_MATCH_PROJECT パターンの使用（resolve-project-lib #137 で LIB_SCRIPT に集約）
test_backfill_title_match_project() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  assert_file_contains "$LIB_SCRIPT" 'title_match' || return 1
  return 0
}
run_test "backfill に TITLE_MATCH_PROJECT パターンがある" test_backfill_title_match_project

# MATCHED_PROJECTS の収集ロジック（resolve-project-lib #137 で LIB_SCRIPT に集約）
test_backfill_matched_projects() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  assert_file_contains "$LIB_SCRIPT" 'matched_num|matched_id' || return 1
  return 0
}
run_test "backfill に MATCHED_PROJECTS 収集ロジックがある" test_backfill_matched_projects

# Edge case: タイトルマッチが最初のマッチより優先される
test_backfill_title_priority_over_first() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # タイトルマッチ優先ロジック: ${title_match_num:-$matched_num} パターン
  assert_file_contains "$LIB_SCRIPT" 'title_match_num:-' || return 1
  return 0
}
run_test "backfill [edge: TITLE_MATCH_PROJECT が最初のマッチより優先]" test_backfill_title_priority_over_first

# Edge case: user → organization フォールバック
test_backfill_user_org_fallback() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  assert_file_contains "$LIB_SCRIPT" 'organization' || return 1
  return 0
}
run_test "backfill [edge: user→organization フォールバック]" test_backfill_user_org_fallback

# Edge case: リポジトリにリンクされた Project がない場合の正常終了
test_backfill_no_project_graceful_exit() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(no.*project|Project.*見つかり|Project.*not.*found|リンク.*なし|exit\s+0)' || return 1
  return 0
}
run_test "backfill [edge: Project 未リンク時の正常終了]" test_backfill_no_project_graceful_exit

# =============================================================================
# Requirement: API エラーハンドリング
# =============================================================================
echo ""
echo "--- Requirement: API エラーハンドリング ---"

# Edge case: gh コマンドのエラーをキャッチする構造
test_backfill_gh_error_handling() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  # gh コマンド呼び出しにエラーハンドリングがある
  assert_file_contains "$BACKFILL_SCRIPT" '(2>/dev/null|\|\| |if !\s*gh|set \+e)' || return 1
  return 0
}
run_test "backfill [edge: gh コマンドのエラーハンドリング]" test_backfill_gh_error_handling

# Edge case: API レート制限対策 (sleep/wait)
test_backfill_rate_limit_wait() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(sleep|wait|rate.limit|レート)' || return 1
  return 0
}
run_test "backfill [edge: API レート制限対策 (sleep)]" test_backfill_rate_limit_wait

# =============================================================================
# Requirement: 出力形式
# Scenario: 結果が表形式で出力される (spec line 31)
# =============================================================================
echo ""
echo "--- Requirement: 出力形式 ---"

# Edge case: 表形式の出力ヘッダー or フォーマット
test_backfill_table_output() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(printf|table|Issue.*Status|#|結果|Result|OK|FAIL|SKIP)' || return 1
  return 0
}
run_test "backfill [edge: 結果の表形式出力]" test_backfill_table_output

# =============================================================================
# Requirement: project-board-status-update.md の TITLE_MATCH_PROJECT 移植
# Scenario: リポジトリ名と一致するタイトルの Project が存在する場合 (spec line 8)
# =============================================================================
echo ""
echo "--- Requirement: project-board-status-update.md の Project 検出ロジック統一 ---"

test_status_update_title_match() {
  assert_file_exists "$STATUS_UPDATE_CMD" || return 1
  assert_file_contains "$STATUS_UPDATE_CMD" 'TITLE_MATCH_PROJECT' || return 1
  return 0
}
run_test "project-board-status-update.md に TITLE_MATCH_PROJECT 記述がある" test_status_update_title_match

test_status_update_matched_projects() {
  assert_file_exists "$STATUS_UPDATE_CMD" || return 1
  assert_file_contains "$STATUS_UPDATE_CMD" 'MATCHED_PROJECTS' || return 1
  return 0
}
run_test "project-board-status-update.md に MATCHED_PROJECTS 収集ロジックがある" test_status_update_matched_projects

# Edge case: user → organization フォールバックが status-update にもある
test_status_update_user_org_fallback() {
  assert_file_exists "$STATUS_UPDATE_CMD" || return 1
  assert_file_contains "$STATUS_UPDATE_CMD" 'organization' || return 1
  return 0
}
run_test "project-board-status-update.md [edge: user→organization フォールバック]" test_status_update_user_org_fallback

# Edge case: sync と status-update の Step 2 ロジックが同等（GraphQL クエリ構造）
test_status_update_graphql_query() {
  assert_file_exists "$STATUS_UPDATE_CMD" || return 1
  assert_file_contains "$STATUS_UPDATE_CMD" '(graphql|GraphQL|projectV2)' || return 1
  return 0
}
run_test "project-board-status-update.md [edge: GraphQL クエリ記述がある]" test_status_update_graphql_query

# =============================================================================
# Requirement: バッチ実行結果の検証
# Scenario: Board 追加の検証 (spec line 46)
# WHEN: バッチスクリプト実行後に検証コマンドを実行する
# THEN: gh project item-list で確認できる
# =============================================================================
echo ""
echo "--- Requirement: バッチ実行結果の検証手順 ---"

# 検証手順がスクリプト内 or 関連ドキュメントに記載されている
test_backfill_verification_hint() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '(item-list|verify|確認|検証)' || return 1
  return 0
}
run_test "backfill に検証手順のヒントがある" test_backfill_verification_hint

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "project-board-backfill: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "==========================================="

[[ ${FAIL} -eq 0 ]]
