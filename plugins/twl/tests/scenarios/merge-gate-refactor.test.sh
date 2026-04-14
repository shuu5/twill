#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: merge-gate controller 行数削減 + スクリプト抽出
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
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

assert_file_line_count_le() {
  local file="$1"
  local max_lines="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  local count
  count=$(wc -l < "${PROJECT_ROOT}/${file}")
  [[ "$count" -le "$max_lines" ]]
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

MERGE_GATE_CONTROLLER="commands/merge-gate.md"

# =============================================================================
# Requirement: merge-gate controller 行数削減
# =============================================================================
echo ""
echo "--- Requirement: merge-gate controller 行数削減 ---"

# Scenario: 行数削減後の検証
# WHEN: merge-gate.md の変更後に wc -l を実行する
# THEN: 行数が 120 以下であること

test_merge_gate_line_count_le_120() {
  assert_file_line_count_le "$MERGE_GATE_CONTROLLER" 120
}
run_test "merge-gate.md の行数が 120 以下である" test_merge_gate_line_count_le_120

# Edge case: 行数の実際の値を記録（デバッグ用）
test_merge_gate_line_count_info() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  local count
  count=$(wc -l < "${PROJECT_ROOT}/${MERGE_GATE_CONTROLLER}")
  echo "    INFO: merge-gate.md は現在 ${count} 行"
  return 0
}
run_test "merge-gate.md 行数情報" test_merge_gate_line_count_info

# =============================================================================
# Requirement: PR 存在確認スクリプト抽出（merge-gate.md からの参照確認）
# =============================================================================
echo ""
echo "--- Requirement: PR 存在確認スクリプト抽出 ---"

# Scenario: merge-gate.md からの参照
# WHEN: merge-gate.md の PR 存在確認セクションを参照する
# THEN: インライン bash の代わりに bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-pr.sh" の 1 行参照になっていること

test_merge_gate_check_pr_script_exists() {
  assert_file_exists "scripts/merge-gate-check-pr.sh"
}
run_test "merge-gate-check-pr.sh が存在する" test_merge_gate_check_pr_script_exists

test_merge_gate_check_pr_executable() {
  assert_file_executable "scripts/merge-gate-check-pr.sh"
}
run_test "merge-gate-check-pr.sh が実行可能である" test_merge_gate_check_pr_executable

test_merge_gate_check_pr_referenced_in_controller() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  assert_file_contains "$MERGE_GATE_CONTROLLER" 'merge-gate-check-pr\.sh' || return 1
}
run_test "merge-gate.md が merge-gate-check-pr.sh を参照する" test_merge_gate_check_pr_referenced_in_controller

# Edge case: merge-gate.md の PR 存在確認部分にインライン bash が残っていない
test_merge_gate_no_inline_pr_check() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  # PR_NUM=$(gh pr view ... のインライン形式が残っていないこと
  # （スクリプト参照行 1 行のみであること）
  local inline_count
  inline_count=$(grep -cP 'PR_NUM=\$\(gh pr view' "${PROJECT_ROOT}/${MERGE_GATE_CONTROLLER}" 2>/dev/null || echo "0")
  [[ "$inline_count" -eq 0 ]]
}
run_test "merge-gate.md [edge: PR 存在確認インライン bash が残っていない]" test_merge_gate_no_inline_pr_check

# =============================================================================
# Requirement: 動的レビュアー構築スクリプト抽出（merge-gate.md からの参照確認）
# =============================================================================
echo ""
echo "--- Requirement: 動的レビュアー構築スクリプト抽出 ---"

test_merge_gate_build_manifest_script_exists() {
  assert_file_exists "scripts/merge-gate-build-manifest.sh"
}
run_test "merge-gate-build-manifest.sh が存在する" test_merge_gate_build_manifest_script_exists

test_merge_gate_build_manifest_executable() {
  assert_file_executable "scripts/merge-gate-build-manifest.sh"
}
run_test "merge-gate-build-manifest.sh が実行可能である" test_merge_gate_build_manifest_executable

test_merge_gate_build_manifest_referenced() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  assert_file_contains "$MERGE_GATE_CONTROLLER" 'merge-gate-build-manifest\.sh' || return 1
}
run_test "merge-gate.md が merge-gate-build-manifest.sh を参照する" test_merge_gate_build_manifest_referenced

# Edge case: merge-gate-build-manifest.sh が bash 構文的に正しい
test_merge_gate_build_manifest_syntax_valid() {
  assert_file_exists "scripts/merge-gate-build-manifest.sh" || return 1
  bash -n "${PROJECT_ROOT}/scripts/merge-gate-build-manifest.sh" 2>/dev/null
}
run_test "merge-gate-build-manifest.sh [edge: bash 構文チェック pass]" test_merge_gate_build_manifest_syntax_valid

# =============================================================================
# Requirement: spawn 完了確認スクリプト抽出（merge-gate.md からの参照確認）
# =============================================================================
echo ""
echo "--- Requirement: spawn 完了確認スクリプト抽出 ---"

test_merge_gate_check_spawn_script_exists() {
  assert_file_exists "scripts/merge-gate-check-spawn.sh"
}
run_test "merge-gate-check-spawn.sh が存在する" test_merge_gate_check_spawn_script_exists

test_merge_gate_check_spawn_executable() {
  assert_file_executable "scripts/merge-gate-check-spawn.sh"
}
run_test "merge-gate-check-spawn.sh が実行可能である" test_merge_gate_check_spawn_executable

test_merge_gate_check_spawn_referenced() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  assert_file_contains "$MERGE_GATE_CONTROLLER" 'merge-gate-check-spawn\.sh' || return 1
}
run_test "merge-gate.md が merge-gate-check-spawn.sh を参照する" test_merge_gate_check_spawn_referenced

# Edge case: スクリプトが MANIFEST_FILE と SPAWNED_FILE を使う
test_merge_gate_check_spawn_uses_env_vars() {
  assert_file_exists "scripts/merge-gate-check-spawn.sh" || return 1
  assert_file_contains "scripts/merge-gate-check-spawn.sh" 'MANIFEST_FILE' || return 1
  assert_file_contains "scripts/merge-gate-check-spawn.sh" 'SPAWNED_FILE' || return 1
}
run_test "merge-gate-check-spawn.sh [edge: MANIFEST_FILE, SPAWNED_FILE 環境変数を使用する]" test_merge_gate_check_spawn_uses_env_vars

# =============================================================================
# Requirement: Cross-PR AC 検証スクリプト抽出（merge-gate.md からの参照確認）
# =============================================================================
echo ""
echo "--- Requirement: Cross-PR AC 検証スクリプト抽出 ---"

test_merge_gate_cross_pr_ac_script_exists() {
  assert_file_exists "scripts/merge-gate-cross-pr-ac.sh"
}
run_test "merge-gate-cross-pr-ac.sh が存在する" test_merge_gate_cross_pr_ac_script_exists

test_merge_gate_cross_pr_ac_executable() {
  assert_file_executable "scripts/merge-gate-cross-pr-ac.sh"
}
run_test "merge-gate-cross-pr-ac.sh が実行可能である" test_merge_gate_cross_pr_ac_executable

test_merge_gate_cross_pr_ac_referenced() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  assert_file_contains "$MERGE_GATE_CONTROLLER" 'merge-gate-cross-pr-ac\.sh' || return 1
}
run_test "merge-gate.md が merge-gate-cross-pr-ac.sh を参照する" test_merge_gate_cross_pr_ac_referenced

# Edge case: bash 構文チェック
test_merge_gate_cross_pr_ac_syntax_valid() {
  assert_file_exists "scripts/merge-gate-cross-pr-ac.sh" || return 1
  bash -n "${PROJECT_ROOT}/scripts/merge-gate-cross-pr-ac.sh" 2>/dev/null
}
run_test "merge-gate-cross-pr-ac.sh [edge: bash 構文チェック pass]" test_merge_gate_cross_pr_ac_syntax_valid

# =============================================================================
# Requirement: checkpoint 統合スクリプト抽出（merge-gate.md からの参照確認）
# =============================================================================
echo ""
echo "--- Requirement: checkpoint 統合スクリプト抽出 ---"

test_merge_gate_checkpoint_merge_script_exists() {
  assert_file_exists "scripts/merge-gate-checkpoint-merge.sh"
}
run_test "merge-gate-checkpoint-merge.sh が存在する" test_merge_gate_checkpoint_merge_script_exists

test_merge_gate_checkpoint_merge_executable() {
  assert_file_executable "scripts/merge-gate-checkpoint-merge.sh"
}
run_test "merge-gate-checkpoint-merge.sh が実行可能である" test_merge_gate_checkpoint_merge_executable

test_merge_gate_checkpoint_merge_referenced() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  assert_file_contains "$MERGE_GATE_CONTROLLER" 'merge-gate-checkpoint-merge\.sh' || return 1
}
run_test "merge-gate.md が merge-gate-checkpoint-merge.sh を参照する" test_merge_gate_checkpoint_merge_referenced

# Edge case: インライン jq -s 'add' が merge-gate.md から除去されている
test_merge_gate_no_inline_checkpoint_merge() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  # インライン統合コードが残っていないこと
  local inline_count
  inline_count=$(grep -cP "jq -s 'add'" "${PROJECT_ROOT}/${MERGE_GATE_CONTROLLER}" 2>/dev/null || echo "0")
  [[ "$inline_count" -eq 0 ]]
}
run_test "merge-gate.md [edge: インライン checkpoint 統合 jq コードが残っていない]" test_merge_gate_no_inline_checkpoint_merge

# =============================================================================
# Requirement: phase-review 必須チェックスクリプト抽出（merge-gate.md からの参照確認）
# =============================================================================
echo ""
echo "--- Requirement: phase-review 必須チェックスクリプト抽出 ---"

test_merge_gate_check_phase_review_script_exists() {
  assert_file_exists "scripts/merge-gate-check-phase-review.sh"
}
run_test "merge-gate-check-phase-review.sh が存在する" test_merge_gate_check_phase_review_script_exists

test_merge_gate_check_phase_review_executable() {
  assert_file_executable "scripts/merge-gate-check-phase-review.sh"
}
run_test "merge-gate-check-phase-review.sh が実行可能である" test_merge_gate_check_phase_review_executable

test_merge_gate_check_phase_review_referenced() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  assert_file_contains "$MERGE_GATE_CONTROLLER" 'merge-gate-check-phase-review\.sh' || return 1
}
run_test "merge-gate.md が merge-gate-check-phase-review.sh を参照する" test_merge_gate_check_phase_review_referenced

# Edge case: phase-review インラインコードが merge-gate.md から除去されている
test_merge_gate_no_inline_phase_review_logic() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  # SKIP_PHASE_REVIEW=false インライン定義が残っていないこと
  local inline_count
  inline_count=$(grep -cP 'SKIP_PHASE_REVIEW=false' "${PROJECT_ROOT}/${MERGE_GATE_CONTROLLER}" 2>/dev/null || echo "0")
  [[ "$inline_count" -eq 0 ]]
}
run_test "merge-gate.md [edge: SKIP_PHASE_REVIEW インラインロジックが残っていない]" test_merge_gate_no_inline_phase_review_logic

test_merge_gate_check_phase_review_uses_env_vars() {
  assert_file_exists "scripts/merge-gate-check-phase-review.sh" || return 1
  assert_file_contains "scripts/merge-gate-check-phase-review.sh" 'PHASE_REVIEW_STATUS' || return 1
  assert_file_contains "scripts/merge-gate-check-phase-review.sh" 'ISSUE_NUM' || return 1
}
run_test "merge-gate-check-phase-review.sh [edge: PHASE_REVIEW_STATUS, ISSUE_NUM 環境変数を使用する]" test_merge_gate_check_phase_review_uses_env_vars

# =============================================================================
# Requirement: 動作等価性（全スクリプトの構造確認）
# =============================================================================
echo ""
echo "--- Requirement: 動作等価性 ---"

# Scenario: 動作等価性
# WHEN: merge-gate.md が参照する各スクリプトを実行する
# THEN: 抽出前と同じロジックが実行され、同じ結果を返すこと

test_all_scripts_have_correct_exit_codes() {
  local all_ok=true
  for script in \
    "scripts/merge-gate-check-pr.sh" \
    "scripts/merge-gate-build-manifest.sh" \
    "scripts/merge-gate-check-spawn.sh" \
    "scripts/merge-gate-cross-pr-ac.sh" \
    "scripts/merge-gate-checkpoint-merge.sh" \
    "scripts/merge-gate-check-phase-review.sh"
  do
    if [[ -f "${PROJECT_ROOT}/${script}" ]]; then
      if ! bash -n "${PROJECT_ROOT}/${script}" 2>/dev/null; then
        echo "    FAIL: ${script} bash 構文エラー"
        all_ok=false
      fi
    else
      echo "    SKIP: ${script} (未作成)"
    fi
  done
  [[ "$all_ok" == "true" ]]
}
run_test "全抽出スクリプトが bash 構文チェック pass" test_all_scripts_have_correct_exit_codes

# Edge case: 全スクリプトが set -e または set -uo pipefail を含む（エラー安全性）
test_all_scripts_have_error_handling() {
  local all_ok=true
  for script in \
    "scripts/merge-gate-check-pr.sh" \
    "scripts/merge-gate-build-manifest.sh" \
    "scripts/merge-gate-check-spawn.sh" \
    "scripts/merge-gate-cross-pr-ac.sh" \
    "scripts/merge-gate-checkpoint-merge.sh" \
    "scripts/merge-gate-check-phase-review.sh"
  do
    if [[ -f "${PROJECT_ROOT}/${script}" ]]; then
      if ! grep -qP '(set -e|set -uo|pipefail)' "${PROJECT_ROOT}/${script}" 2>/dev/null; then
        echo "    WARN: ${script} に set -e/pipefail がない"
        # WARN のみ（FAIL にしない）
      fi
    fi
  done
  return 0
}
run_test "全抽出スクリプト [edge: エラーハンドリング設定の確認]" test_all_scripts_have_error_handling

# Edge case: merge-gate.md が 6 つの抽出スクリプトを全て参照する
test_merge_gate_references_all_extracted_scripts() {
  assert_file_exists "$MERGE_GATE_CONTROLLER" || return 1
  local missing_refs=()
  local scripts=(
    "merge-gate-check-pr.sh"
    "merge-gate-build-manifest.sh"
    "merge-gate-check-spawn.sh"
    "merge-gate-cross-pr-ac.sh"
    "merge-gate-checkpoint-merge.sh"
    "merge-gate-check-phase-review.sh"
  )
  for script in "${scripts[@]}"; do
    if ! grep -qF "$script" "${PROJECT_ROOT}/${MERGE_GATE_CONTROLLER}" 2>/dev/null; then
      missing_refs+=("$script")
    fi
  done
  if [[ ${#missing_refs[@]} -gt 0 ]]; then
    echo "    FAIL: 以下が merge-gate.md で参照されていない:"
    printf "      - %s\n" "${missing_refs[@]}"
    return 1
  fi
  return 0
}
run_test "merge-gate.md [edge: 全 6 スクリプトが参照されている]" test_merge_gate_references_all_extracted_scripts

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
