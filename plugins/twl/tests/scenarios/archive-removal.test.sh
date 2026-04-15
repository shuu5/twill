#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: archive-removal (issue-598)
# Generated from: deltaspec/changes/issue-598/specs/archive-removal.md
# Coverage level: edge-cases
# Verifies:
#   - autopilot-orchestrator.sh の archive 関連コード削除
#   - chain-runner.sh の gh project item-list --limit 200 確認
#   - chain-runner.sh の step_board_archive 関数保持
#   - project-board-backfill.sh の --limit 500 維持
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

ORCHESTRATOR_SH="scripts/autopilot-orchestrator.sh"
CHAIN_RUNNER_SH="scripts/chain-runner.sh"
BACKFILL_SH="scripts/project-board-backfill.sh"

# =============================================================================
# Requirement: 自動 archive 処理の除去（Bash）
# =============================================================================
echo ""
echo "--- Requirement: 自動 archive 処理の除去（Bash）---"

# Scenario: merge-gate 成功後の自動 archive 除去 (line 7)
# WHEN: merge-gate が成功する
# THEN: archive_done_issues は呼び出されず、Done アイテムが Project Board に残ること

test_archive_done_issues_function_removed() {
  # archive_done_issues 関数定義が存在しないこと
  assert_file_not_contains "$ORCHESTRATOR_SH" "^archive_done_issues\(\)"
}

run_test "autopilot-orchestrator.sh: archive_done_issues() 関数定義が削除されている" \
  test_archive_done_issues_function_removed

test_archive_deltaspec_function_removed() {
  # _archive_deltaspec_changes_for_issue 関数定義が存在しないこと
  assert_file_not_contains "$ORCHESTRATOR_SH" "^_archive_deltaspec_changes_for_issue\(\)"
}

run_test "autopilot-orchestrator.sh: _archive_deltaspec_changes_for_issue() 関数定義が削除されている" \
  test_archive_deltaspec_function_removed

test_skipped_archives_global_removed() {
  # SKIPPED_ARCHIVES グローバル配列宣言が存在しないこと
  assert_file_not_contains "$ORCHESTRATOR_SH" "SKIPPED_ARCHIVES=\(\)"
}

run_test "autopilot-orchestrator.sh: SKIPPED_ARCHIVES グローバル配列が削除されている" \
  test_skipped_archives_global_removed

test_archive_done_issues_call_removed() {
  # archive_done_issues の呼び出しが存在しないこと（関数定義行とは別に呼び出し箇所も検査）
  assert_file_not_contains "$ORCHESTRATOR_SH" "archive_done_issues "
}

run_test "autopilot-orchestrator.sh: archive_done_issues の呼び出し箇所が全て削除されている" \
  test_archive_done_issues_call_removed

# Scenario: phase report から skipped_archives フィールドの除去 (line 11)
# WHEN: フェーズレポートが生成される
# THEN: skipped_archives フィールドが JSON 出力に含まれないこと

test_skipped_archives_field_in_report_removed() {
  # skipped_archives フィールドがレポート JSON 生成に含まれないこと
  assert_file_not_contains "$ORCHESTRATOR_SH" "skipped_archives"
}

run_test "autopilot-orchestrator.sh: フェーズレポートから skipped_archives フィールドが削除されている" \
  test_skipped_archives_field_in_report_removed

# Edge case: _do_archive ネスト関数も削除されていること
test_do_archive_nested_removed() {
  assert_file_not_contains "$ORCHESTRATOR_SH" "_do_archive\(\)"
}

run_test "autopilot-orchestrator.sh [edge: _do_archive ネスト関数が削除されている]" \
  test_do_archive_nested_removed

# Edge case: 「twl spec archive」呼び出しが orchestrator から除去されていること
test_twl_spec_archive_call_removed() {
  assert_file_not_contains "$ORCHESTRATOR_SH" "twl spec archive"
}

run_test "autopilot-orchestrator.sh [edge: 'twl spec archive' 呼び出しが削除されている]" \
  test_twl_spec_archive_call_removed

# Edge case: archive 関連コメントが存在しない（「archive は呼び出されず」を確認するため
# コメント自体の存在も検査する）
test_archive_call_comment_removed() {
  # "先に archive を実行" のようなフロー制御コメントが消えていること
  assert_file_not_contains "$ORCHESTRATOR_SH" "先に archive を実行"
}

run_test "autopilot-orchestrator.sh [edge: 'archive 実行' 制御コメントが削除されている]" \
  test_archive_call_comment_removed

# =============================================================================
# Requirement: gh project item-list の limit 統一確認
# =============================================================================
echo ""
echo "--- Requirement: gh project item-list の limit 統一確認 ---"

# Scenario: limit 200 確認（chain-runner.sh）(line 34)
# WHEN: chain-runner.sh 内で gh project item-list が実行される
# THEN: --limit 200 が指定されていること

test_chain_runner_limit_200() {
  assert_file_contains "$CHAIN_RUNNER_SH" "gh project item-list.*--limit 200|--limit 200.*gh project item-list"
}

run_test "chain-runner.sh: gh project item-list の --limit が 200 である" \
  test_chain_runner_limit_200

# Edge case: chain-runner.sh に --limit 100 や --limit 50 など古い値が残っていないこと
test_chain_runner_no_old_limit() {
  # 100 や 50 が item-list の --limit として残っていないこと（backfill は別ファイル）
  if grep -qP "gh project item-list" "${PROJECT_ROOT}/${CHAIN_RUNNER_SH}" 2>/dev/null; then
    # item-list が存在する場合、--limit 200 以外の値が使われていないこと
    ! grep -qP "gh project item-list.*--limit (?!200)\d+" "${PROJECT_ROOT}/${CHAIN_RUNNER_SH}" 2>/dev/null
  else
    return 0  # item-list 自体がなければスキップ扱いで OK
  fi
}

run_test "chain-runner.sh [edge: --limit 200 以外の item-list limit 値が存在しない]" \
  test_chain_runner_no_old_limit

# Scenario: backfill スクリプトは除外 (line 37)
# WHEN: project-board-backfill.sh 内で gh project item-list が実行される
# THEN: --limit 500 が意図的に維持されていること（全件取得のため）

test_backfill_limit_500() {
  assert_file_contains "$BACKFILL_SH" "gh project item-list.*--limit 500|--limit 500.*gh project item-list"
}

run_test "project-board-backfill.sh: gh project item-list の --limit が 500 のまま維持されている" \
  test_backfill_limit_500

# Edge case: backfill が --limit 200 に誤って変更されていないこと
test_backfill_not_changed_to_200() {
  if grep -qP "gh project item-list" "${PROJECT_ROOT}/${BACKFILL_SH}" 2>/dev/null; then
    assert_file_not_contains "$BACKFILL_SH" "gh project item-list.*--limit 200"
  else
    return 0
  fi
}

run_test "project-board-backfill.sh [edge: --limit が誤って 200 に変更されていない]" \
  test_backfill_not_changed_to_200

# =============================================================================
# Requirement: chain-runner.sh の手動 archive 機能保持
# =============================================================================
echo ""
echo "--- Requirement: chain-runner.sh の手動 archive 機能保持 ---"

# Scenario: 手動 archive 機能の保持 (line 44)
# WHEN: chain-runner.sh の step_board_archive が参照される
# THEN: 関数が存在し、呼び出し可能であること

test_step_board_archive_function_exists() {
  assert_file_contains "$CHAIN_RUNNER_SH" "step_board_archive\(\)"
}

run_test "chain-runner.sh: step_board_archive() 関数が削除されずに存在する" \
  test_step_board_archive_function_exists

test_step_board_archive_dispatch_registered() {
  # board-archive のディスパッチ登録が存在すること
  assert_file_contains "$CHAIN_RUNNER_SH" "board-archive"
}

run_test "chain-runner.sh: 'board-archive' ステップとして登録されている" \
  test_step_board_archive_dispatch_registered

# Edge case: step_board_archive 内に gh project item-archive 呼び出しが含まれること
test_step_board_archive_calls_gh() {
  # gh project コマンド（archive 操作）が step_board_archive 内に存在すること
  # 関数内に gh item-archive または gh project edit（archive相当）があること
  assert_file_contains "$CHAIN_RUNNER_SH" "item-archive\|archive-item\|gh project.*item"
}

run_test "chain-runner.sh [edge: step_board_archive が gh project 操作を含む]" \
  test_step_board_archive_calls_gh

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
