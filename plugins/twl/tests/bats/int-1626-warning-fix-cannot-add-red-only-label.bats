#!/usr/bin/env bats
# int-1626-warning-fix-cannot-add-red-only-label.bats
#
# Issue #1626 AC5.3 — warning-fix label add escape hatch 閉鎖の regression test
#
# AC5: warning-fix Worker が `gh pr edit --add-label red-only` を実行して
#      AC2 escape hatch を悪用しようとしても、AC1 の AND 条件 (follow-up Issue 不在) で
#      再度 CRITICAL が発行される（label add だけでは escape できない）。
#
# 検証シナリオ:
#   1. 初回: red-only label なし + RED-only → CRITICAL (既存)
#   2. warning-fix Worker が red-only label を追加 (gh pr edit --add-label red-only)
#   3. 再 merge-gate 実行: red-only label 付き + follow-up 不在 → AC1 で CRITICAL 維持
#   4. follow-up Issue 起票後の再実行: red-only + follow-up 存在 → WARNING 降格

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
# AC5.3-a: 初回 (label なし) → CRITICAL
# ===========================================================================

@test "ac5.3a: 初回 RED-only PR (label なし) → CRITICAL (regression baseline)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  stub_command "gh" 'echo "[]"'

  local pr_json='{"number":42,"labels":[],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success
  assert_output --partial "CRITICAL"
}

# ===========================================================================
# AC5.3-b: warning-fix で label 付与 → AC1 で CRITICAL 維持 (escape 不能)
# ===========================================================================

@test "ac5.3b: warning-fix が red-only label add → AC1 で CRITICAL 維持 (escape 不能)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # warning-fix Worker が gh pr edit --add-label red-only 実行後を模擬
  # PR JSON は label 付き、follow-up Issue は未起票のまま
  stub_command "gh" 'echo "[]"'

  local pr_json='{"number":42,"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success
  # AC1: follow-up 不在のため WARNING ではなく CRITICAL になる (escape hatch 閉鎖)
  assert_output --partial "CRITICAL"
  assert_output --partial "follow-up Issue"
  refute_output --partial "WARNING"
}

# ===========================================================================
# AC5.3-c: follow-up 起票後 → WARNING 降格 (TDD 正規 path)
# ===========================================================================

@test "ac5.3c: follow-up Issue 起票後の再実行 → WARNING 降格 (TDD 正規 path 復活)" {
  local script="${SCRIPTS_DIR}/worker-red-only-detector.sh"
  [ -f "$script" ]

  # 起票済み follow-up Issue
  stub_command "gh" '
cat <<JSON_EOF
[{"number":888,"body":"<!-- follow-up-for: PR #42 -->\n## 概要..."}]
JSON_EOF'

  local pr_json='{"number":42,"labels":[{"name":"red-only"}],"files":[{"path":"plugins/twl/tests/bats/sample.bats"}]}'
  run bash "$script" --pr-json "$pr_json"
  assert_success
  assert_output --partial "WARNING"
  assert_output --partial "存在を確認"
  refute_output --partial "CRITICAL"
}
