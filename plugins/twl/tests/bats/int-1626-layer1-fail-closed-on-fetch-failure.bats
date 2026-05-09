#!/usr/bin/env bats
# int-1626-layer1-fail-closed-on-fetch-failure.bats
#
# Issue #1626 AC4.4 — Layer 1 fail-closed の integration test
#
# AC4: merge-gate-check-red-only.sh で `git diff --name-only origin/main` が
#      失敗した場合に `gh pr view --json files` で fallback。双方失敗時は
#      fail-closed REJECT (exit 1)。silent PASS (exit 0) は禁止。
#
# 検証シナリオ:
#   1. git diff origin/main 失敗 + git diff HEAD 失敗 + gh pr view 失敗 → exit 1 (fail-closed)
#   2. git diff origin/main 失敗 + gh pr view 成功（test ファイルのみ） → REJECT exit 1
#   3. git diff origin/main 失敗 + gh pr view 成功（impl ファイル含む） → exit 0 (PASS)
#   4. git diff origin/main 成功（impl ファイル含む） → exit 0 (PASS、fallback 不要)

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
# AC4.4-a: 全 fetch 失敗 → fail-closed REJECT
# ===========================================================================

@test "ac4.4a: git diff + gh pr view 双方失敗 → fail-closed REJECT (exit 1)" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git diff も gh pr view も全て失敗（exit 1）
  stub_command "git" 'exit 1'
  stub_command "gh" 'exit 1'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_failure
  assert_output --partial "fail-closed"
  assert_output --partial "変更ファイル取得不能"
}

# ===========================================================================
# AC4.4-b: git diff 失敗 + gh pr view 成功（test only） → REJECT
# ===========================================================================

@test "ac4.4b: git diff 失敗 + gh pr view fallback (test only) → REJECT" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git diff 全失敗
  stub_command "git" 'exit 1'

  # gh pr view --json files は test ファイルのみ返す
  stub_command "gh" '
case "$*" in
  *"pr view"*"files"*) echo "plugins/twl/tests/bats/sample.bats" ;;
  *"pr view"*"number"*) echo "" ;;  # PR 番号取得失敗
  *"pr view"*"labels"*) echo "false" ;;
  *"issue list"*) echo "[]" ;;
  *) exit 1 ;;
esac'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_failure
  assert_output --partial "REJECT: RED-only PR"
}

# ===========================================================================
# AC4.4-c: git diff 失敗 + gh pr view 成功（impl 含む） → PASS
# ===========================================================================

@test "ac4.4c: git diff 失敗 + gh pr view fallback (impl 含む) → PASS exit 0" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  stub_command "git" 'exit 1'

  # gh pr view が impl ファイルを含む変更ファイルリストを返す
  stub_command "gh" '
case "$*" in
  *"pr view"*"files"*)
    echo "plugins/twl/scripts/some-impl.sh"
    echo "plugins/twl/tests/bats/sample.bats"
    ;;
  *) exit 1 ;;
esac'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_success
}

# ===========================================================================
# AC4.4-d: git diff 成功 (impl 含む) → PASS（fallback 不要）
# ===========================================================================

@test "ac4.4d: git diff 成功 (impl 含む) → PASS exit 0（fallback 不要）" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # git diff origin/main が impl ファイルを返す（gh は呼ばれないはず）
  stub_command "git" '
case "$*" in
  *"diff"*"--name-only"*"origin/main"*)
    echo "plugins/twl/scripts/some-impl.sh"
    ;;
  *) exit 1 ;;
esac'

  # gh は呼ばれない想定だが念のため stub
  stub_command "gh" 'exit 1'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_success
}

# ===========================================================================
# AC4.4-e: git diff origin/main 失敗 + git diff HEAD 成功 → 通常 path
# ===========================================================================

@test "ac4.4e: git diff origin/main 失敗 + HEAD 成功 (test only) → REJECT" {
  local script="${SCRIPTS_DIR}/merge-gate-check-red-only.sh"
  [ -f "$script" ]

  # origin/main は失敗、HEAD は成功
  stub_command "git" '
case "$*" in
  *"diff"*"--name-only"*"origin/main"*) exit 1 ;;
  *"diff"*"--name-only"*"HEAD"*) echo "plugins/twl/tests/bats/sample.bats" ;;
  *) exit 1 ;;
esac'

  stub_command "gh" '
case "$*" in
  *"pr view"*"number"*) echo "" ;;
  *) exit 1 ;;
esac'

  run bash "${SANDBOX}/scripts/merge-gate-check-red-only.sh"
  assert_failure
  assert_output --partial "REJECT: RED-only PR"
}
