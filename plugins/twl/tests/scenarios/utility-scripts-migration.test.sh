#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: utility-scripts.md
# Generated from: openspec/changes/c-4-scripts-migration/specs/utility-scripts.md
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

PARSE_ISSUE_AC="scripts/parse-issue-ac.sh"
SESSION_AUDIT="scripts/session-audit.sh"
CHECK_DB_MIGRATION="scripts/check-db-migration.py"
ECC_MONITOR="scripts/ecc-monitor.sh"

# =============================================================================
# Requirement: parse-issue-ac スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: parse-issue-ac スクリプト移植 ---"

# Scenario: AC 抽出 (line 17)
# WHEN: Issue 番号が指定される
# THEN: Issue body から受け入れ基準（AC）セクションが抽出される

test_parse_issue_ac_exists() {
  assert_file_exists "$PARSE_ISSUE_AC"
}
run_test "parse-issue-ac.sh が存在する" test_parse_issue_ac_exists

test_parse_issue_ac_executable() {
  assert_file_executable "$PARSE_ISSUE_AC"
}
run_test "parse-issue-ac.sh が実行可能である" test_parse_issue_ac_executable

test_parse_issue_ac_gh_integration() {
  assert_file_exists "$PARSE_ISSUE_AC" || return 1
  # gh issue view または gh api 呼び出し
  assert_file_contains "$PARSE_ISSUE_AC" '(gh issue|gh api)' || return 1
  return 0
}
run_test "parse-issue-ac.sh に gh CLI による Issue 取得がある" test_parse_issue_ac_gh_integration

test_parse_issue_ac_extraction() {
  assert_file_exists "$PARSE_ISSUE_AC" || return 1
  # AC セクション抽出ロジック
  assert_file_contains "$PARSE_ISSUE_AC" '(AC|acceptance|criteria|受け入れ)' || return 1
  return 0
}
run_test "parse-issue-ac.sh に AC セクション抽出ロジックがある" test_parse_issue_ac_extraction

# Edge case: AC セクションが存在しない Issue の処理
test_parse_issue_ac_missing_section() {
  assert_file_exists "$PARSE_ISSUE_AC" || return 1
  assert_file_contains "$PARSE_ISSUE_AC" '(empty|not.*found|no.*ac|missing|warn)' || return 1
  return 0
}
run_test "parse-issue-ac.sh [edge: AC セクション不在時の処理]" test_parse_issue_ac_missing_section

# =============================================================================
# Requirement: session-audit スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: session-audit スクリプト移植 ---"

# Scenario: セッション事後分析 (line 24)
# WHEN: bash scripts/session-audit.sh を実行する
# THEN: session.json から JSONL ログを分析し、5カテゴリのワークフロー信頼性問題を検出する

test_session_audit_exists() {
  assert_file_exists "$SESSION_AUDIT"
}
run_test "session-audit.sh が存在する" test_session_audit_exists

test_session_audit_executable() {
  assert_file_executable "$SESSION_AUDIT"
}
run_test "session-audit.sh が実行可能である" test_session_audit_executable

test_session_audit_session_json() {
  assert_file_exists "$SESSION_AUDIT" || return 1
  # JSONL ファイルベースで動作する（session.json → jsonl-path に変更済み）
  assert_file_contains "$SESSION_AUDIT" '(jsonl|JSONL_PATH|session)' || return 1
  return 0
}
run_test "session-audit.sh が JSONL ファイルベースで動作する" test_session_audit_session_json

test_session_audit_no_env_var() {
  assert_file_exists "$SESSION_AUDIT" || return 1
  # DEV_AUTOPILOT_SESSION 環境変数参照が排除されていること
  assert_file_not_contains "$SESSION_AUDIT" 'DEV_AUTOPILOT_SESSION' || return 1
  return 0
}
run_test "session-audit.sh に DEV_AUTOPILOT_SESSION 参照がない" test_session_audit_no_env_var

test_session_audit_five_categories() {
  assert_file_exists "$SESSION_AUDIT" || return 1
  # 監査カテゴリ: tool_call / tool_result / ai_text / skill_call / metadata
  assert_file_contains "$SESSION_AUDIT" '(tool_call|tool_result|ai_text|skill_call|metadata)' || return 1
  return 0
}
run_test "session-audit.sh に監査カテゴリ抽出ロジックがある" test_session_audit_five_categories

# Edge case: JSONL ログ解析
test_session_audit_jsonl_parsing() {
  assert_file_exists "$SESSION_AUDIT" || return 1
  assert_file_contains "$SESSION_AUDIT" '(jsonl|jq|json|log)' || return 1
  return 0
}
run_test "session-audit.sh [edge: JSONL ログ解析処理]" test_session_audit_jsonl_parsing

# =============================================================================
# Requirement: check-db-migration スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: check-db-migration スクリプト移植 ---"

# Scenario: DB マイグレーションチェック (line 32)
# WHEN: python3 scripts/check-db-migration.py を実行する
# THEN: マイグレーションファイルの整合性が検証される

test_check_db_migration_exists() {
  assert_file_exists "$CHECK_DB_MIGRATION"
}
run_test "check-db-migration.py が存在する" test_check_db_migration_exists

test_check_db_migration_python() {
  assert_file_exists "$CHECK_DB_MIGRATION" || return 1
  # Python スクリプトであること
  assert_file_contains "$CHECK_DB_MIGRATION" '(#!/.*python|import |def )' || return 1
  return 0
}
run_test "check-db-migration.py が Python スクリプトである" test_check_db_migration_python

test_check_db_migration_integrity() {
  assert_file_exists "$CHECK_DB_MIGRATION" || return 1
  assert_file_contains "$CHECK_DB_MIGRATION" '(migration|integrity|check|verify|valid)' || return 1
  return 0
}
run_test "check-db-migration.py にマイグレーション整合性検証がある" test_check_db_migration_integrity

# Edge case: Python 構文の正当性
test_check_db_migration_syntax() {
  assert_file_exists "$CHECK_DB_MIGRATION" || return 1
  python3 -m py_compile "${PROJECT_ROOT}/${CHECK_DB_MIGRATION}" 2>/dev/null
}
run_test "check-db-migration.py [edge: Python 構文が正しい]" test_check_db_migration_syntax

# =============================================================================
# Requirement: ecc-monitor スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: ecc-monitor スクリプト移植 ---"

# Scenario: ECC 変更検知 (line 40)
# WHEN: bash scripts/ecc-monitor.sh を実行する
# THEN: ECC リポジトリの最新変更が検出され、関連性が評価される

test_ecc_monitor_exists() {
  assert_file_exists "$ECC_MONITOR"
}
run_test "ecc-monitor.sh が存在する" test_ecc_monitor_exists

test_ecc_monitor_executable() {
  assert_file_executable "$ECC_MONITOR"
}
run_test "ecc-monitor.sh が実行可能である" test_ecc_monitor_executable

test_ecc_monitor_change_detection() {
  assert_file_exists "$ECC_MONITOR" || return 1
  assert_file_contains "$ECC_MONITOR" '(git.*log|git.*diff|commit|change|detect)' || return 1
  return 0
}
run_test "ecc-monitor.sh に変更検出ロジックがある" test_ecc_monitor_change_detection

test_ecc_monitor_relevance() {
  assert_file_exists "$ECC_MONITOR" || return 1
  # カテゴリ分類ロジック（classify_path 関数）で変更内容を評価
  assert_file_contains "$ECC_MONITOR" '(classify|category|agents|skills|rules|hooks)' || return 1
  return 0
}
run_test "ecc-monitor.sh にカテゴリ分類ロジックがある" test_ecc_monitor_relevance

# Edge case: ECC リポジトリが存在しない場合
test_ecc_monitor_repo_missing() {
  assert_file_exists "$ECC_MONITOR" || return 1
  assert_file_contains "$ECC_MONITOR" '(exist|not.*found|missing|clone|error)' || return 1
  return 0
}
run_test "ecc-monitor.sh [edge: リポジトリ不在時のエラーハンドリング]" test_ecc_monitor_repo_missing

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "utility-scripts-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
