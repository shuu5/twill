#!/usr/bin/env bats
# int-1626-followup-verify-and-condition.bats
#
# Issue #1626 AC1.6 — follow-up Issue 機械的 verify (AND 条件) の integration test
#
# AC1: worker-red-only-detector.sh の red-only label 判定で follow-up Issue 存在を
#      AND 条件として検証する。
#      - red-only + follow-up 不在 → CRITICAL 昇格 (escape hatch 閉鎖)
#      - red-only + follow-up 存在 → WARNING 維持 (TDD RED phase 正規 path)
#      - gh 失敗 / PR_NUMBER 不明 → graceful skip → WARNING 維持
#
# 検証シナリオ:
#   1. red-only label + PR_NUMBER + follow-up 不在 → CRITICAL 昇格
#   2. red-only label + PR_NUMBER + follow-up 存在 → WARNING 維持
#   3. red-only label + PR_NUMBER + gh 失敗 → WARNING 維持 (graceful)
#   4. red-only label + PR_NUMBER 不明 → WARNING 維持 (graceful)
#   5. red-only label なし + RED-only → CRITICAL (既存挙動)

load 'helpers/common'

SCRIPTS_DIR=""

setup() {
  common_setup
  SCRIPTS_DIR="${REPO_ROOT}/scripts"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1.6-a: red-only + follow-up 不在 → CRITICAL 昇格
# ===========================================================================

@test "ac1.6a: red-only label + follow-up 不在 → CRITICAL 昇格 (escape hatch 閉鎖)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh issue list が空配列 = follow-up 不在
  stub_command "gh" 'echo "[]"'

  local pr_json='{"number":42,"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success  # exit 0 常時 (CRITICAL は stdout に出る)
  assert_output --partial "CRITICAL"
  assert_output --partial "follow-up Issue"
  assert_output --partial "不在"
  refute_output --partial "WARNING"
}

# ===========================================================================
# AC1.6-b: red-only + follow-up 存在 → WARNING 維持
# ===========================================================================

@test "ac1.6b: red-only label + follow-up 存在 → WARNING 維持 (TDD 正規 path)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh issue list が marker 付き Issue を返す = follow-up 存在
  stub_command "gh" '
cat <<JSON_EOF
[{"number":888,"body":"<!-- follow-up-for: PR #42 -->\n本文"}]
JSON_EOF'

  local pr_json='{"number":42,"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success
  assert_output --partial "WARNING"
  assert_output --partial "存在を確認"
  refute_output --partial "CRITICAL"
}

# ===========================================================================
# AC1.6-c: red-only + gh 失敗 → graceful skip (WARNING 維持)
# ===========================================================================

@test "ac1.6c: red-only label + gh 失敗 → graceful skip (WARNING 維持)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh が exit 1 (認証失敗 / API エラー)
  stub_command "gh" 'exit 1'

  local pr_json='{"number":42,"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success
  assert_output --partial "WARNING"
  assert_output --partial "follow-up"
  assert_output --partial "verify"
  refute_output --partial "CRITICAL"
}

# ===========================================================================
# AC1.6-d: red-only + PR_NUMBER 不明 → graceful skip (WARNING 維持、既存テスト互換)
# ===========================================================================

@test "ac1.6d: red-only label + PR_NUMBER 不明 → graceful skip (既存テスト互換)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh stub なし → デフォルト挙動でも skip 動作（PR_NUMBER 不明で skip）
  stub_command "gh" 'echo "[]"'

  # number フィールドなし
  local pr_json='{"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success
  assert_output --partial "WARNING"
  refute_output --partial "CRITICAL"
}

# ===========================================================================
# AC1.6-e: red-only label なし → CRITICAL (既存挙動、regression guard)
# ===========================================================================

@test "ac1.6e: red-only label なし + RED-only → CRITICAL (既存挙動、regression guard)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # gh は呼ばれないが念のため stub
  stub_command "gh" 'echo "[]"'

  local pr_json='{"number":42,"labels":[],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success
  assert_output --partial "CRITICAL"
  refute_output --partial "WARNING"
}
