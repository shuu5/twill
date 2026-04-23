#!/usr/bin/env bats
# merge-gate-check-phase-review.bats - unit tests for scripts/merge-gate-check-phase-review.sh
# Generated from: deltaspec/changes/issue-680/specs/merge-gate-refactor.md
# Requirement: phase-review 必須チェックスクリプト抽出
# Coverage: unit + edge-cases

load '../helpers/common'

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  export ISSUE_NUM="42"
  # デフォルト: phase-review checkpoint が PASS の状態を作成
  mkdir -p "$SANDBOX/.autopilot/checkpoints"
  echo '{"step":"phase-review","status":"PASS","findings":[]}' \
    > "$SANDBOX/.autopilot/checkpoints/phase-review.json"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: phase-review 必須チェックスクリプト抽出
# ---------------------------------------------------------------------------

@test "merge-gate-check-phase-review.sh が存在する" {
  [[ -f "$SANDBOX/scripts/merge-gate-check-phase-review.sh" ]]
}

@test "merge-gate-check-phase-review.sh が実行可能である" {
  [[ -x "$SANDBOX/scripts/merge-gate-check-phase-review.sh" ]]
}

@test "merge-gate-check-phase-review.sh が bash 構文チェック pass" {
  bash -n "$SANDBOX/scripts/merge-gate-check-phase-review.sh"
}

# ---------------------------------------------------------------------------
# Scenario: phase-review チェックスクリプト実行
# WHEN: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-phase-review.sh" が呼び出される
# THEN: phase-review が不在の場合は REJECT を返す（全 Issue 必須）
# ---------------------------------------------------------------------------

@test "phase-review checkpoint が PASS の場合は exit 0 を返す" {
  # setup で PASS checkpoint を作成済み

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_success
}

@test "phase-review checkpoint が不在の場合は exit 1 (REJECT) を返す" {
  rm -f "$SANDBOX/.autopilot/checkpoints/phase-review.json"

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_failure
}

@test "phase-review checkpoint が不在の場合は REJECT メッセージを出力する" {
  rm -f "$SANDBOX/.autopilot/checkpoints/phase-review.json"

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh" 2>&1

  assert_output --partial "REJECT"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "[edge] checkpoint が不在の場合は MISSING として扱う" {
  rm -f "$SANDBOX/.autopilot/checkpoints/phase-review.json"

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh"

  assert_failure
}

@test "[edge] --force フラグで checkpoint 不在でも WARNING を出して継続する" {
  rm -f "$SANDBOX/.autopilot/checkpoints/phase-review.json"

  run bash "$SANDBOX/scripts/merge-gate-check-phase-review.sh" --force 2>&1

  assert_success
  assert_output --partial "WARNING"
}
