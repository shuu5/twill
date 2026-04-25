#!/usr/bin/env bats
# specialist-audit-mode-symmetry.bats
# AC C-1: fixture-based regression test
#
# specialist-audit.sh が出力した既存の FAIL JSON fixture を読み込み、
# 修正前の状態（worker-architecture が missing、worker-issue-pr-alignment が extra）を確認する。
# 実際に specialist-audit.sh は実行しない。JSON fixture のフィールドを jq で検査する。

load '../helpers/common'

MAIN_REPO_ROOT="/home/shuu5/projects/local-projects/twill/main"

setup() {
  common_setup
  # Resolve fixture dir from bats standard variable (avoids BASH_SOURCE[0] tempfile issue)
  FIXTURE_DIR="$(cd "$BATS_TEST_DIRNAME/../../fixtures/specialist-audit" && pwd)"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Fixture ファイル存在確認
# ===========================================================================

@test "C-1 fixture: specialist-audit-963 JSON exists in main repo .audit dir" {
  [[ -d "$MAIN_REPO_ROOT/.audit" ]] || skip "MAIN_REPO_ROOT .audit dir not available (CI environment)"
  run ls -la "${MAIN_REPO_ROOT}/.audit/20260425-110509/specialist-audit-963-1777082709849176995-2292910.json"
  assert_success
}

@test "C-1 fixture: specialist-audit-962 JSON exists in main repo .audit dir" {
  [[ -d "$MAIN_REPO_ROOT/.audit" ]] || skip "MAIN_REPO_ROOT .audit dir not available (CI environment)"
  run ls -la "${MAIN_REPO_ROOT}/.audit/20260425-110510/specialist-audit-962-1777082710046179863-2293028.json"
  assert_success
}

@test "C-1 fixture: specialist-audit-964 JSON exists in main repo .audit dir" {
  [[ -d "$MAIN_REPO_ROOT/.audit" ]] || skip "MAIN_REPO_ROOT .audit dir not available (CI environment)"
  run ls -la "${MAIN_REPO_ROOT}/.audit/20260425-140944/specialist-audit-964-1777093784086158351-2892684.json"
  assert_success
}

@test "C-1 fixture: specialist-audit-963 JSON exists in test fixtures dir" {
  run ls -la "${FIXTURE_DIR}/specialist-audit-963-1777082709849176995-2292910.json"
  assert_success
}

@test "C-1 fixture: specialist-audit-962 JSON exists in test fixtures dir" {
  run ls -la "${FIXTURE_DIR}/specialist-audit-962-1777082710046179863-2293028.json"
  assert_success
}

@test "C-1 fixture: specialist-audit-964 JSON exists in test fixtures dir" {
  run ls -la "${FIXTURE_DIR}/specialist-audit-964-1777093784086158351-2892684.json"
  assert_success
}

# ===========================================================================
# C-1: missing フィールドに worker-architecture が含まれること（修正前の FAIL 状態確認）
# issue #963: missing=["worker-architecture","worker-code-reviewer","worker-codex-reviewer","worker-security-reviewer"]
# ===========================================================================

@test "C-1 regression: specialist-audit-963 missing contains worker-architecture" {
  local fixture="${FIXTURE_DIR}/specialist-audit-963-1777082709849176995-2292910.json"
  run jq -r '.missing[]' "${fixture}"
  assert_success
  assert_output --partial "worker-architecture"
}

# ===========================================================================
# issue #962: missing=["worker-architecture"]
# ===========================================================================

@test "C-1 regression: specialist-audit-962 missing contains worker-architecture" {
  local fixture="${FIXTURE_DIR}/specialist-audit-962-1777082710046179863-2293028.json"
  run jq -r '.missing[]' "${fixture}"
  assert_success
  assert_output --partial "worker-architecture"
}

# ===========================================================================
# issue #964: missing=["worker-architecture"]
# ===========================================================================

@test "C-1 regression: specialist-audit-964 missing contains worker-architecture" {
  local fixture="${FIXTURE_DIR}/specialist-audit-964-1777093784086158351-2892684.json"
  run jq -r '.missing[]' "${fixture}"
  assert_success
  assert_output --partial "worker-architecture"
}

# ===========================================================================
# C-1: extra フィールドに worker-issue-pr-alignment が含まれること
# issue #963: extra=[] → 含まない（例外ケース）
# ===========================================================================

@test "C-1 regression: specialist-audit-963 extra does NOT contain worker-issue-pr-alignment" {
  local fixture="${FIXTURE_DIR}/specialist-audit-963-1777082709849176995-2292910.json"
  run jq -r '.extra[]' "${fixture}"
  # extra=[] なので出力なし、worker-issue-pr-alignment は含まれない
  refute_output --partial "worker-issue-pr-alignment"
}

# ===========================================================================
# issue #962: extra=["worker-issue-pr-alignment"]
# ===========================================================================

@test "C-1 regression: specialist-audit-962 extra contains worker-issue-pr-alignment" {
  local fixture="${FIXTURE_DIR}/specialist-audit-962-1777082710046179863-2293028.json"
  run jq -r '.extra[]' "${fixture}"
  assert_success
  assert_output --partial "worker-issue-pr-alignment"
}

# ===========================================================================
# issue #964: extra=["worker-issue-pr-alignment"]
# ===========================================================================

@test "C-1 regression: specialist-audit-964 extra contains worker-issue-pr-alignment" {
  local fixture="${FIXTURE_DIR}/specialist-audit-964-1777093784086158351-2892684.json"
  run jq -r '.extra[]' "${fixture}"
  assert_success
  assert_output --partial "worker-issue-pr-alignment"
}

# ===========================================================================
# C-1: 各 fixture の status が FAIL であること（修正前確認）
# ===========================================================================

@test "C-1 regression: specialist-audit-963 status is FAIL" {
  local fixture="${FIXTURE_DIR}/specialist-audit-963-1777082709849176995-2292910.json"
  run jq -r '.status' "${fixture}"
  assert_success
  assert_output "FAIL"
}

@test "C-1 regression: specialist-audit-962 status is FAIL" {
  local fixture="${FIXTURE_DIR}/specialist-audit-962-1777082710046179863-2293028.json"
  run jq -r '.status' "${fixture}"
  assert_success
  assert_output "FAIL"
}

@test "C-1 regression: specialist-audit-964 status is FAIL" {
  local fixture="${FIXTURE_DIR}/specialist-audit-964-1777093784086158351-2892684.json"
  run jq -r '.status' "${fixture}"
  assert_success
  assert_output "FAIL"
}

# ===========================================================================
# C-1: mode が merge-gate であること
# ===========================================================================

@test "C-1 regression: all fixtures have mode merge-gate (963)" {
  local fixture="${FIXTURE_DIR}/specialist-audit-963-1777082709849176995-2292910.json"
  run jq -r '.mode' "${fixture}"
  assert_success
  assert_output "merge-gate"
}

@test "C-1 regression: all fixtures have mode merge-gate (962)" {
  local fixture="${FIXTURE_DIR}/specialist-audit-962-1777082710046179863-2293028.json"
  run jq -r '.mode' "${fixture}"
  assert_success
  assert_output "merge-gate"
}

@test "C-1 regression: all fixtures have mode merge-gate (964)" {
  local fixture="${FIXTURE_DIR}/specialist-audit-964-1777093784086158351-2892684.json"
  run jq -r '.mode' "${fixture}"
  assert_success
  assert_output "merge-gate"
}
