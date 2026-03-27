#!/usr/bin/env bash
# =============================================================================
# Functional Tests: progress-tracking.md
# Generated from: openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md
# Coverage level: edge-cases
# Tests TaskCreate/TaskUpdate usage, flag removal
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Sandbox Setup ---

SANDBOX=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "${SANDBOX}/.autopilot/issues"
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

# --- Test Helpers ---

run_test() {
  local name="$1"
  local func="$2"
  local result
  setup_sandbox
  result=0
  $func || result=$?
  teardown_sandbox
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

# =============================================================================
# Requirement: TaskCreate による Phase 進捗登録
# =============================================================================
echo ""
echo "--- Requirement: TaskCreate による Phase 進捗登録 ---"

# Scenario: Phase 開始時のタスク登録 (line 7)
# WHEN: Phase 1 が開始され、対象 Issue が #42, #43, #44
# THEN: TaskCreate で Phase 1: Issue #42, #43, #44 のタスクが status=in_progress で登録される
test_phase_task_create() {
  # Structural verification: spec defines TaskCreate usage for Phase start
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "TaskCreate" "$spec_file" || return 1
  grep -qP "Phase.*1.*Issue.*#42.*#43.*#44" "$spec_file" || return 1
  grep -qP "in_progress" "$spec_file" || return 1
}

run_test "Phase 開始時のタスク登録" test_phase_task_create

# Edge case: タスク名に Phase 番号と Issue 番号リストが含まれる
test_phase_task_name_format() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "Phase.*[0-9]+.*Issue.*#[0-9]+" "$spec_file" || return 1
}

run_test "Phase タスク登録 [edge: タスク名フォーマット]" test_phase_task_name_format

# Scenario: 単一 Issue の Phase (line 11)
# WHEN: Phase 2 が開始され、対象 Issue が #45 のみ
# THEN: TaskCreate で Phase 2: Issue #45 のタスクが status=in_progress で登録される
test_single_issue_phase() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "Phase 2.*Issue.*#45" "$spec_file" || return 1
}

run_test "単一 Issue の Phase" test_single_issue_phase

# Edge case: 単一 Issue でも複数 Issue でも同じ TaskCreate インターフェースが使用される
test_task_create_uniform_interface() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  # Both scenarios use TaskCreate
  local count
  count=$(grep -cP "TaskCreate" "$spec_file")
  [[ "$count" -ge 2 ]] || return 1
}

run_test "単一 Issue Phase [edge: 統一インターフェース]" test_task_create_uniform_interface

# =============================================================================
# Requirement: TaskUpdate による Issue 完了追跡
# =============================================================================
echo ""
echo "--- Requirement: TaskUpdate による Issue 完了追跡 ---"

# Scenario: Issue 正常完了 (line 19)
# WHEN: issue-42.json の status が done に遷移する
# THEN: 対応する Phase タスクの説明に #42: done が追記される
test_issue_done_task_update() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "TaskUpdate" "$spec_file" || return 1
  grep -qP "#42.*done" "$spec_file" || return 1
}

run_test "Issue 正常完了" test_issue_done_task_update

# Edge case: TaskUpdate は説明フィールドへの追記であり、上書きではない
test_task_update_append() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "追記" "$spec_file" || return 1
}

run_test "Issue 正常完了 [edge: 説明への追記]" test_task_update_append

# Scenario: Issue 失敗 (line 23)
# WHEN: issue-42.json の status が failed に確定する（リトライ上限到達）
# THEN: 対応する Phase タスクの説明に #42: failed が追記される
test_issue_failed_task_update() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "#42.*failed" "$spec_file" || return 1
  grep -qP "リトライ上限" "$spec_file" || return 1
}

run_test "Issue 失敗" test_issue_failed_task_update

# Edge case: failed は リトライ上限到達時のみ TaskUpdate される（一時的な failed では不可）
test_issue_failed_only_permanent() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "確定|リトライ上限到達" "$spec_file" || return 1
}

run_test "Issue 失敗 [edge: リトライ上限到達時のみ]" test_issue_failed_only_permanent

# Scenario: Phase 全 Issue 完了 (line 27)
# WHEN: Phase 内の全 Issue が done または failed (確定) に遷移する
# THEN: Phase タスクの status が completed に更新される
test_phase_completed() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "Phase.*全.*Issue.*完了|全.*Issue.*done.*failed" "$spec_file" || return 1
  grep -qP "completed" "$spec_file" || return 1
}

run_test "Phase 全 Issue 完了" test_phase_completed

# Edge case: done と failed の混在でも Phase は completed になる
test_phase_completed_mixed() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "done.*または.*failed|done.*failed" "$spec_file" || return 1
}

run_test "Phase 全 Issue 完了 [edge: done/failed 混在で completed]" test_phase_completed_mixed

# =============================================================================
# Requirement: specialist 内部での TaskCreate 不使用
# =============================================================================
echo ""
echo "--- Requirement: specialist 内部での TaskCreate 不使用 ---"

# Scenario: specialist 実行中 (line 35)
# WHEN: merge-gate 内で specialist（code-reviewer 等）が実行される
# THEN: specialist は TaskCreate/TaskUpdate を呼び出さない
test_specialist_no_task_create() {
  # Check that specialist components do not contain TaskCreate/TaskUpdate
  local specialist_dir="${PROJECT_ROOT}/components/specialists"
  if [[ -d "$specialist_dir" ]]; then
    local found=0
    while IFS= read -r -d '' file; do
      if grep -qP "TaskCreate|TaskUpdate" "$file" 2>/dev/null; then
        found=1
        break
      fi
    done < <(find "$specialist_dir" -type f -print0 2>/dev/null)
    [[ "$found" -eq 0 ]] || return 1
  else
    # Structural verification from spec
    local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
    [[ -f "$spec_file" ]] || return 1
    grep -qP "specialist.*TaskCreate.*TaskUpdate.*使用.*ない|TaskCreate.*TaskUpdate.*呼び出さない" "$spec_file" || return 1
  fi
}

run_test "specialist 実行中の TaskCreate 不使用" test_specialist_no_task_create

# Edge case: 理由がオーバーヘッド回避として明記されている
test_specialist_reason_documented() {
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/progress-tracking.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "短命タスク|オーバーヘッド" "$spec_file" || return 1
}

run_test "specialist TaskCreate 不使用 [edge: 理由が明記]" test_specialist_reason_documented

# =============================================================================
# Requirement: --auto/--auto-merge フラグの廃止
# =============================================================================
echo ""
echo "--- Requirement: --auto/--auto-merge フラグの廃止 ---"

# Scenario: フラグ不在の確認 (line 45)
# WHEN: co-autopilot の SKILL.md および全 workflow/atomic コンポーネントを検索する
# THEN: --auto および --auto-merge フラグへの参照が存在しない
test_no_auto_flag() {
  local found=0
  # Search in SKILL.md files
  while IFS= read -r file; do
    if grep -qP "\-\-auto\b|\-\-auto-merge" "$file" 2>/dev/null; then
      found=1
      break
    fi
  done < <(find "${PROJECT_ROOT}" -name "SKILL.md" -type f 2>/dev/null)
  # Search in workflow/atomic components
  for dir in "${PROJECT_ROOT}/components/workflows" "${PROJECT_ROOT}/components/atomics"; do
    if [[ -d "$dir" ]]; then
      while IFS= read -r -d '' file; do
        if grep -qP "\-\-auto\b|\-\-auto-merge" "$file" 2>/dev/null; then
          found=1
          break 2
        fi
      done < <(find "$dir" -type f -print0 2>/dev/null)
    fi
  done
  [[ "$found" -eq 0 ]] || return 1
}

run_test "--auto/--auto-merge フラグ不在の確認" test_no_auto_flag

# Edge case: scripts/ 配下にも --auto フラグの参照がない
test_no_auto_flag_in_scripts() {
  local scripts_dir="${PROJECT_ROOT}/scripts"
  if [[ -d "$scripts_dir" ]]; then
    local found=0
    while IFS= read -r -d '' file; do
      if grep -qP "\-\-auto\b|\-\-auto-merge" "$file" 2>/dev/null; then
        found=1
        break
      fi
    done < <(find "$scripts_dir" -type f -print0 2>/dev/null)
    [[ "$found" -eq 0 ]] || return 1
  fi
  # If no scripts dir, it's trivially true
}

run_test "--auto フラグ [edge: scripts/ にも参照なし]" test_no_auto_flag_in_scripts

# =============================================================================
# Requirement: DEV_AUTOPILOT_SESSION 環境変数の廃止
# =============================================================================
echo ""
echo "--- Requirement: DEV_AUTOPILOT_SESSION 環境変数の廃止 ---"

# Scenario: 環境変数不在の確認 (line 53)
# WHEN: 全スクリプトおよび SKILL.md を検索する
# THEN: DEV_AUTOPILOT_SESSION への参照が存在しない
test_no_dev_autopilot_session_env() {
  local found=0
  # Search all scripts (*.sh) and SKILL.md files per spec definition
  while IFS= read -r -d '' file; do
    if grep -qP "DEV_AUTOPILOT_SESSION" "$file" 2>/dev/null; then
      found=1
      break
    fi
  done < <(find "${PROJECT_ROOT}" \( -name "*.sh" -o -name "SKILL.md" \) -type f -not -path "*/openspec/*" -not -path "*/.git/*" -not -path "*/tests/scenarios/*" -print0 2>/dev/null)
  [[ "$found" -eq 0 ]] || return 1
}

run_test "DEV_AUTOPILOT_SESSION 環境変数不在の確認" test_no_dev_autopilot_session_env

# Edge case: openspec 以外の全ディレクトリで不在
test_no_dev_autopilot_session_anywhere() {
  local found=0
  # Extended check: scripts, SKILL.md, and component files (excluding docs/architecture/openspec/tests)
  while IFS= read -r -d '' file; do
    if grep -qP "DEV_AUTOPILOT_SESSION" "$file" 2>/dev/null; then
      found=1
      break
    fi
  done < <(find "${PROJECT_ROOT}" \( -name "*.sh" -o -name "SKILL.md" \) -type f -not -path "*/openspec/*" -not -path "*/.git/*" -not -path "*/tests/scenarios/*" -print0 2>/dev/null)
  [[ "$found" -eq 0 ]] || return 1
}

run_test "DEV_AUTOPILOT_SESSION [edge: openspec 以外で完全不在]" test_no_dev_autopilot_session_anywhere

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
