#!/usr/bin/env bats
# session-create.bats - unit tests for scripts/session-create.sh

load '../helpers/common'

setup() {
  common_setup
  # Ensure no session.json exists
  rm -f "$SANDBOX/.autopilot/session.json"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: session management scripts unit test
# ---------------------------------------------------------------------------

# Scenario: session.json creation
@test "session-create creates session.json with required fields" {
  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$SANDBOX/.autopilot/plan.yaml" \
    --phase-count 3

  assert_success
  assert_output --partial "OK: session.json"

  [ -f "$SANDBOX/.autopilot/session.json" ]

  # Verify required fields
  jq -e '.session_id' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.plan_path' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.current_phase == 1' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.phase_count == 3' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.started_at' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.cross_issue_warnings | type == "array"' "$SANDBOX/.autopilot/session.json" > /dev/null
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "session-create fails if session.json already exists" {
  create_session_json

  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$SANDBOX/.autopilot/plan.yaml" \
    --phase-count 2

  assert_failure
  assert_output --partial "既に存在します"
}

@test "session-create fails without --plan-path" {
  run bash "$SANDBOX/scripts/session-create.sh" \
    --phase-count 2

  assert_failure
  assert_output --partial "--plan-path"
}

@test "session-create fails without --phase-count" {
  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$SANDBOX/.autopilot/plan.yaml"

  assert_failure
  assert_output --partial "--phase-count"
}

@test "session-create fails with non-numeric phase-count" {
  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$SANDBOX/.autopilot/plan.yaml" \
    --phase-count abc

  assert_failure
  assert_output --partial "正の整数"
}

@test "session-create generates 8-char hex session_id" {
  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$SANDBOX/.autopilot/plan.yaml" \
    --phase-count 1

  assert_success

  local sid
  sid=$(jq -r '.session_id' "$SANDBOX/.autopilot/session.json")
  [ ${#sid} -eq 8 ]
  [[ "$sid" =~ ^[0-9a-f]+$ ]]
}

@test "session-create creates .autopilot dir if missing" {
  rm -rf "$SANDBOX/.autopilot"

  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$SANDBOX/.autopilot/plan.yaml" \
    --phase-count 1

  assert_success
  [ -d "$SANDBOX/.autopilot" ]
  [ -f "$SANDBOX/.autopilot/session.json" ]
}
