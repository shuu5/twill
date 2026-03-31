#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: PILOT_AUTOPILOT_DIR default value fix
# Generated from: openspec/changes/fix-pilotautopilotdir-empty-default/specs/default-autopilot-dir/spec.md
# Coverage level: edge-cases
# Verifies: commands/autopilot-phase-execute.md resolve_issue_repo_context()
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

TARGET_CMD="commands/autopilot-phase-execute.md"

# =============================================================================
# Requirement: 単一リポジトリ時の PILOT_AUTOPILOT_DIR デフォルト値設定
# =============================================================================
echo ""
echo "--- Requirement: 単一リポジトリ時の PILOT_AUTOPILOT_DIR デフォルト値設定 ---"

# Scenario: 単一リポジトリで resolve_issue_repo_context を呼び出す
# WHEN: repo_id が _default である
# THEN: PILOT_AUTOPILOT_DIR は ${PROJECT_DIR}/.autopilot に設定される

test_default_branch_sets_autopilot_dir() {
  # else ブランチで PILOT_AUTOPILOT_DIR に ${PROJECT_DIR}/.autopilot が設定されていることを検証
  # LLM コンテキスト依存の $AUTOPILOT_DIR ではなく、明示的な絶対パスで設定
  assert_file_contains "$TARGET_CMD" 'PILOT_AUTOPILOT_DIR=.*\${PROJECT_DIR}/\.autopilot'
}

run_test "単一リポジトリ時に PILOT_AUTOPILOT_DIR が \${PROJECT_DIR}/.autopilot に設定される" \
  test_default_branch_sets_autopilot_dir

test_no_empty_pilotautopilotdir() {
  # else ブランチで PILOT_AUTOPILOT_DIR="" が存在しないことを検証
  assert_file_not_contains "$TARGET_CMD" 'PILOT_AUTOPILOT_DIR=""'
}

run_test "PILOT_AUTOPILOT_DIR に空文字列が設定されていない" \
  test_no_empty_pilotautopilotdir

# Scenario: クロスリポジトリで resolve_issue_repo_context を呼び出す
# WHEN: repo_id が _default でなく、REPOS_JSON が設定されている
# THEN: PILOT_AUTOPILOT_DIR は ${PROJECT_DIR}/.autopilot に設定される（既存動作）

test_cross_repo_sets_project_dir() {
  assert_file_contains "$TARGET_CMD" 'PILOT_AUTOPILOT_DIR=.*PROJECT_DIR.*\.autopilot'
}

run_test "クロスリポジトリ時に PILOT_AUTOPILOT_DIR が \${PROJECT_DIR}/.autopilot に設定される" \
  test_cross_repo_sets_project_dir

# Scenario: Worker が AUTOPILOT_DIR を受け取る（autopilot-launch 側）
# WHEN: 単一リポジトリで autopilot-launch が Worker を起動する
# THEN: Worker の AUTOPILOT_DIR 環境変数に Pilot の $AUTOPILOT_DIR が設定される

test_launch_passes_autopilot_dir() {
  # autopilot-launch.md で PILOT_AUTOPILOT_DIR が Worker に渡される仕組みが存在する
  assert_file_contains "commands/autopilot-launch.md" 'PILOT_AUTOPILOT_DIR'
}

run_test "autopilot-launch が PILOT_AUTOPILOT_DIR を Worker に渡す仕組みが存在する" \
  test_launch_passes_autopilot_dir

# --- Edge case: resolve_issue_repo_context 関数が存在する ---

test_resolve_function_exists() {
  assert_file_contains "$TARGET_CMD" 'resolve_issue_repo_context'
}

run_test "resolve_issue_repo_context 関数が定義されている" \
  test_resolve_function_exists

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Results ==="
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"
echo "  SKIP: ${SKIP}"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - ${e}"
  done
fi

exit "${FAIL}"
