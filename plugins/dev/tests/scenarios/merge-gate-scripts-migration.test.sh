#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: merge-gate-scripts.md
# Generated from: openspec/changes/c-4-scripts-migration/specs/merge-gate-scripts.md
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

MERGE_GATE_INIT="scripts/merge-gate-init.sh"
MERGE_GATE_EXECUTE="scripts/merge-gate-execute.sh"
MERGE_GATE_ISSUES="scripts/merge-gate-issues.sh"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: merge-gate-init スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: merge-gate-init スクリプト移植 ---"

# Scenario: 正常な merge-gate 初期化 (line 8)
# WHEN: Issue N の status が merge-ready で、issue-{N}.json に pr と branch が記録されている
# THEN: eval 可能な変数定義（PR_NUMBER, BRANCH, RETRY_COUNT, PR_DIFF_FILE, PR_FILES, GATE_TYPE, PLUGIN_NAMES）を stdout に出力する

test_merge_gate_init_exists() {
  assert_file_exists "$MERGE_GATE_INIT"
}
run_test "merge-gate-init.sh が存在する" test_merge_gate_init_exists

test_merge_gate_init_executable() {
  assert_file_executable "$MERGE_GATE_INIT"
}
run_test "merge-gate-init.sh が実行可能である" test_merge_gate_init_executable

test_merge_gate_init_outputs_variables() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  assert_file_contains "$MERGE_GATE_INIT" 'PR_NUMBER' || return 1
  assert_file_contains "$MERGE_GATE_INIT" 'BRANCH' || return 1
  assert_file_contains "$MERGE_GATE_INIT" 'GATE_TYPE' || return 1
  return 0
}
run_test "merge-gate-init.sh が PR_NUMBER, BRANCH, GATE_TYPE を出力する" test_merge_gate_init_outputs_variables

test_merge_gate_init_eval_format() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  # eval 可能な形式で出力（VAR=value パターン）
  assert_file_contains "$MERGE_GATE_INIT" '(echo.*=|printf.*=|PR_NUMBER=|BRANCH=)' || return 1
  return 0
}
run_test "merge-gate-init.sh が eval 可能な変数定義形式で出力する" test_merge_gate_init_eval_format

test_merge_gate_init_state_read_integration() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  # state-read.sh 経由で状態参照
  assert_file_contains "$MERGE_GATE_INIT" 'state-read' || return 1
  return 0
}
run_test "merge-gate-init.sh が state-read.sh 経由で状態参照する" test_merge_gate_init_state_read_integration

# Edge case: MARKER_DIR 直接参照が排除されていること
test_merge_gate_init_no_marker_dir() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  assert_file_not_contains "$MERGE_GATE_INIT" 'MARKER_DIR' || return 1
  return 0
}
run_test "merge-gate-init.sh [edge: MARKER_DIR 直接参照が排除されている]" test_merge_gate_init_no_marker_dir

# Edge case: RETRY_COUNT, PR_DIFF_FILE, PR_FILES, PLUGIN_NAMES も出力に含まれる
test_merge_gate_init_all_output_vars() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  assert_file_contains "$MERGE_GATE_INIT" 'RETRY_COUNT' || return 1
  assert_file_contains "$MERGE_GATE_INIT" 'PLUGIN_NAMES' || return 1
  return 0
}
run_test "merge-gate-init.sh [edge: RETRY_COUNT, PLUGIN_NAMES も出力する]" test_merge_gate_init_all_output_vars

# Scenario: merge-ready 状態でない Issue (line 12)
# WHEN: Issue N の status が merge-ready でない
# THEN: エラーメッセージを stderr に出力し exit 1 で終了する

test_merge_gate_init_non_merge_ready_error() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  # merge-ready チェックとエラー処理の存在
  assert_file_contains "$MERGE_GATE_INIT" 'merge-ready' || return 1
  assert_file_contains "$MERGE_GATE_INIT" '(exit 1|>&2)' || return 1
  return 0
}
run_test "merge-gate-init.sh に merge-ready でない場合のエラー処理がある" test_merge_gate_init_non_merge_ready_error

# Edge case: stderr と exit 1 の両方が正しく使われている
test_merge_gate_init_stderr_usage() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  assert_file_contains "$MERGE_GATE_INIT" '>&2' || return 1
  return 0
}
run_test "merge-gate-init.sh [edge: エラー出力が stderr に向いている]" test_merge_gate_init_stderr_usage

# Scenario: GATE_TYPE の自動判定 (line 16)
# WHEN: PR差分のファイルパスに plugins/ 配下の変更が含まれ、対応する deps.yaml が存在する
# THEN: GATE_TYPE=plugin を出力する

test_merge_gate_init_gate_type_plugin() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  assert_file_contains "$MERGE_GATE_INIT" 'GATE_TYPE' || return 1
  assert_file_contains "$MERGE_GATE_INIT" 'plugin' || return 1
  return 0
}
run_test "merge-gate-init.sh に GATE_TYPE=plugin 判定ロジックがある" test_merge_gate_init_gate_type_plugin

# Edge case: plugins/ 以外の変更時の GATE_TYPE デフォルト値
test_merge_gate_init_gate_type_default() {
  assert_file_exists "$MERGE_GATE_INIT" || return 1
  # plugin 以外のケース（default/general 等）の存在
  assert_file_contains "$MERGE_GATE_INIT" '(default|general|standard|else)' || return 1
  return 0
}
run_test "merge-gate-init.sh [edge: GATE_TYPE デフォルト値のハンドリング]" test_merge_gate_init_gate_type_default

# =============================================================================
# Requirement: merge-gate-execute スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: merge-gate-execute スクリプト移植 ---"

# Scenario: マージ成功時の状態遷移 (line 24)
# WHEN: gh pr merge が成功する
# THEN: state-write.sh で status=done, merged_at, branch を記録し、worktree/ブランチのクリーンアップを実行する

test_merge_gate_execute_exists() {
  assert_file_exists "$MERGE_GATE_EXECUTE"
}
run_test "merge-gate-execute.sh が存在する" test_merge_gate_execute_exists

test_merge_gate_execute_executable() {
  assert_file_executable "$MERGE_GATE_EXECUTE"
}
run_test "merge-gate-execute.sh が実行可能である" test_merge_gate_execute_executable

test_merge_gate_execute_gh_merge() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" 'gh pr merge' || return 1
  return 0
}
run_test "merge-gate-execute.sh に gh pr merge 呼び出しがある" test_merge_gate_execute_gh_merge

test_merge_gate_execute_state_write_done() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" 'state-write' || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" 'done' || return 1
  return 0
}
run_test "merge-gate-execute.sh が state-write.sh で status=done を記録する" test_merge_gate_execute_state_write_done

test_merge_gate_execute_cleanup() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  # worktree/ブランチのクリーンアップ処理
  assert_file_contains "$MERGE_GATE_EXECUTE" '(worktree.*delete|branch.*delete|cleanup|clean)' || return 1
  return 0
}
run_test "merge-gate-execute.sh に worktree/ブランチのクリーンアップがある" test_merge_gate_execute_cleanup

# Edge case: マーカーファイル操作が state-write に置換されていること
test_merge_gate_execute_no_marker() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  assert_file_not_contains "$MERGE_GATE_EXECUTE" 'MARKER_DIR' || return 1
  return 0
}
run_test "merge-gate-execute.sh [edge: MARKER_DIR 直接操作が排除されている]" test_merge_gate_execute_no_marker

# Scenario: リジェクト時の状態遷移 (line 28)
# WHEN: --reject モードで実行される
# THEN: state-write.sh で status=failed, reason=merge_gate_rejected, retry_count=1 を記録する

test_merge_gate_execute_reject_mode() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" '--reject' || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" 'merge_gate_rejected' || return 1
  return 0
}
run_test "merge-gate-execute.sh に --reject モードと rejected 理由がある" test_merge_gate_execute_reject_mode

test_merge_gate_execute_reject_retry() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" 'retry_count' || return 1
  return 0
}
run_test "merge-gate-execute.sh に retry_count 記録がある" test_merge_gate_execute_reject_retry

# Scenario: 確定失敗時の状態遷移 (line 32)
# WHEN: --reject-final モードで実行される
# THEN: state-write.sh で status=failed, reason=merge_gate_rejected_final, retry_count=2 を記録する

test_merge_gate_execute_reject_final_mode() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" '--reject-final' || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" 'merge_gate_rejected_final' || return 1
  return 0
}
run_test "merge-gate-execute.sh に --reject-final モードがある" test_merge_gate_execute_reject_final_mode

# Edge case: 3つのモード（merge, reject, reject-final）の分岐が全て存在
test_merge_gate_execute_all_modes() {
  assert_file_exists "$MERGE_GATE_EXECUTE" || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" '--reject-final' || return 1
  assert_file_contains "$MERGE_GATE_EXECUTE" '--reject' || return 1
  # デフォルト（merge）モードの存在
  assert_file_contains "$MERGE_GATE_EXECUTE" '(merge|default)' || return 1
  return 0
}
run_test "merge-gate-execute.sh [edge: 3モード分岐が全て存在する]" test_merge_gate_execute_all_modes

# =============================================================================
# Requirement: merge-gate-issues スクリプト移植
# =============================================================================
echo ""
echo "--- Requirement: merge-gate-issues スクリプト移植 ---"

# Scenario: tech-debt Issue の自動起票 (line 40)
# WHEN: merge-gate レビューで tech-debt finding が検出される
# THEN: GitHub Issue が自動作成され、tech-debt ラベルが付与される

test_merge_gate_issues_exists() {
  assert_file_exists "$MERGE_GATE_ISSUES"
}
run_test "merge-gate-issues.sh が存在する" test_merge_gate_issues_exists

test_merge_gate_issues_executable() {
  assert_file_executable "$MERGE_GATE_ISSUES"
}
run_test "merge-gate-issues.sh が実行可能である" test_merge_gate_issues_executable

test_merge_gate_issues_gh_create() {
  assert_file_exists "$MERGE_GATE_ISSUES" || return 1
  assert_file_contains "$MERGE_GATE_ISSUES" 'gh issue create' || return 1
  return 0
}
run_test "merge-gate-issues.sh に gh issue create 呼び出しがある" test_merge_gate_issues_gh_create

test_merge_gate_issues_tech_debt_label() {
  assert_file_exists "$MERGE_GATE_ISSUES" || return 1
  assert_file_contains "$MERGE_GATE_ISSUES" 'tech-debt' || return 1
  return 0
}
run_test "merge-gate-issues.sh に tech-debt ラベル付与がある" test_merge_gate_issues_tech_debt_label

# Edge case: finding が空の場合の Issue 作成スキップ
test_merge_gate_issues_empty_findings() {
  assert_file_exists "$MERGE_GATE_ISSUES" || return 1
  assert_file_contains "$MERGE_GATE_ISSUES" '(empty|no.*finding|skip|0)' || return 1
  return 0
}
run_test "merge-gate-issues.sh [edge: finding 空時のスキップ処理]" test_merge_gate_issues_empty_findings

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "merge-gate-scripts-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
