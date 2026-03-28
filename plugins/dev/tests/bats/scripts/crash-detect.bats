#!/usr/bin/env bats
# crash-detect.bats - unit tests for scripts/crash-detect.sh

load '../helpers/common'

setup() {
  common_setup
  # stub tmux by default (no panes = crash)
  stub_command "tmux" 'exit 1'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: crash-detect unit test
# ---------------------------------------------------------------------------

# Scenario: pane absent -> crash detection (exit 2, status -> failed)
@test "crash-detect detects crash when tmux pane is absent" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  # Verify status changed to failed
  local new_status
  new_status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$new_status" = "failed" ]

  # Verify failure info was written
  local failure_msg
  failure_msg=$(jq -r '.failure.message' "$SANDBOX/.autopilot/issues/issue-1.json")
  [[ "$failure_msg" == *"crash"* ]] || [[ "$failure_msg" == *"disappeared"* ]]
}

# Scenario: non-running status is skipped (exit 0)
@test "crash-detect skips non-running issue with exit 0" {
  create_issue_json 1 "done"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "crash-detect exits 0 when tmux pane exists" {
  create_issue_json 1 "running"
  stub_command "tmux" 'exit 0'

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

@test "crash-detect skips merge-ready status" {
  create_issue_json 1 "merge-ready"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

@test "crash-detect skips failed status" {
  create_issue_json 1 "failed"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

@test "crash-detect fails without --issue" {
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --window "ap-#1"

  assert_failure
  assert_output --partial "--issue"
}

@test "crash-detect fails without --window" {
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1

  assert_failure
  assert_output --partial "--window"
}

@test "crash-detect fails with non-numeric issue" {
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue abc --window "ap-#1"

  assert_failure
  assert_output --partial "正の整数"
}

@test "crash-detect with nonexistent issue file (state-read returns empty)" {
  # No issue json created -- state-read returns empty, status != running
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 99 --window "ap-#99"

  # status would be empty string, which is != "running", so exit 0
  assert_success
}
