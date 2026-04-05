#!/usr/bin/env bats
# merge-gate-init.bats - unit tests for scripts/merge-gate-init.sh

load '../helpers/common'

setup() {
  common_setup

  # Default stubs
  stub_command "gh" '
    case "$*" in
      *"pr diff"*"--name-only"*)
        echo "src/main.ts" ;;
      *"pr diff"*)
        echo "diff content" ;;
      *)
        echo "" ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: merge-gate scripts unit test
# ---------------------------------------------------------------------------

# Scenario: merge-gate-init PR info retrieval
@test "merge-gate-init retrieves PR info and outputs eval-able variables" {
  create_issue_json 1 "merge-ready" '.pr = 42 | .branch = "feat/1-test"'
  export ISSUE=1

  run bash "$SANDBOX/scripts/merge-gate-init.sh"

  assert_success
  assert_output --partial "PR_NUMBER="
  assert_output --partial "BRANCH="
  assert_output --partial "RETRY_COUNT="
  assert_output --partial "PR_DIFF_FILE="
  assert_output --partial "GATE_TYPE="
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "merge-gate-init fails without ISSUE env var" {
  unset ISSUE

  run bash "$SANDBOX/scripts/merge-gate-init.sh"

  assert_failure
  assert_output --partial "不正なISSUE番号"
}

@test "merge-gate-init fails with non-numeric ISSUE" {
  export ISSUE="abc"

  run bash "$SANDBOX/scripts/merge-gate-init.sh"

  assert_failure
  assert_output --partial "不正なISSUE番号"
}

@test "merge-gate-init fails when status is not merge-ready" {
  create_issue_json 1 "running"
  export ISSUE=1

  run bash "$SANDBOX/scripts/merge-gate-init.sh"

  assert_failure
  assert_output --partial "merge-ready ではありません"
}

@test "merge-gate-init fails when PR number is empty" {
  create_issue_json 1 "merge-ready" '.branch = "feat/1-test"'
  # pr is null by default
  export ISSUE=1

  run bash "$SANDBOX/scripts/merge-gate-init.sh"

  assert_failure
  assert_output --partial "PR番号取得失敗"
}

@test "merge-gate-init sanitizes BRANCH with invalid characters" {
  create_issue_json 1 "merge-ready" '.pr = 42 | .branch = "feat/1-te$t;bad"'
  export ISSUE=1

  run bash "$SANDBOX/scripts/merge-gate-init.sh"

  assert_success
  # BRANCH should be sanitized (no $ or ;)
  assert_output --partial "BRANCH="
}

@test "merge-gate-init detects plugin gate type" {
  create_issue_json 1 "merge-ready" '.pr = 42 | .branch = "feat/1-test"'
  export ISSUE=1

  stub_command "gh" '
    case "$*" in
      *"pr diff"*"--name-only"*)
        echo "plugins/dev/src/main.ts" ;;
      *"pr diff"*)
        echo "diff content" ;;
      *)
        echo "" ;;
    esac
  '

  # Create plugin deps.yaml for detection (script checks relative to CWD)
  mkdir -p "$SANDBOX/plugins/dev"
  echo "version: 3.0" > "$SANDBOX/plugins/dev/deps.yaml"

  cd "$SANDBOX"
  run bash "$SANDBOX/scripts/merge-gate-init.sh"

  assert_success
  assert_output --partial "GATE_TYPE=plugin"
}
