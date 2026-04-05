#!/usr/bin/env bats
# session-add-warning.bats - unit tests for scripts/session-add-warning.sh

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: session management scripts unit test
# ---------------------------------------------------------------------------

# Scenario: warning addition
@test "session-add-warning appends warning to session.json" {
  create_session_json

  run bash "$SANDBOX/scripts/session-add-warning.sh" \
    --issue 1 --target-issue 2 --file "src/main.ts" --reason "concurrent edit"

  assert_success
  assert_output --partial "OK: cross-issue 警告を追加しました"

  # Verify warning was added
  local count
  count=$(jq '.cross_issue_warnings | length' "$SANDBOX/.autopilot/session.json")
  [ "$count" -eq 1 ]

  # Verify warning content
  jq -e '.cross_issue_warnings[0].issue == 1' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.cross_issue_warnings[0].target_issue == 2' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.cross_issue_warnings[0].file == "src/main.ts"' "$SANDBOX/.autopilot/session.json" > /dev/null
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "session-add-warning fails without required args" {
  create_session_json

  run bash "$SANDBOX/scripts/session-add-warning.sh" \
    --issue 1

  assert_failure
  assert_output --partial "必須"
}

@test "session-add-warning fails when session.json does not exist" {
  rm -f "$SANDBOX/.autopilot/session.json"

  run bash "$SANDBOX/scripts/session-add-warning.sh" \
    --issue 1 --target-issue 2 --file "a.ts" --reason "test"

  assert_failure
  assert_output --partial "session.json が存在しません"
}

@test "session-add-warning can add multiple warnings" {
  create_session_json

  bash "$SANDBOX/scripts/session-add-warning.sh" \
    --issue 1 --target-issue 2 --file "a.ts" --reason "first"
  bash "$SANDBOX/scripts/session-add-warning.sh" \
    --issue 3 --target-issue 4 --file "b.ts" --reason "second"

  local count
  count=$(jq '.cross_issue_warnings | length' "$SANDBOX/.autopilot/session.json")
  [ "$count" -eq 2 ]
}

@test "session-add-warning preserves existing session.json data" {
  create_session_json

  bash "$SANDBOX/scripts/session-add-warning.sh" \
    --issue 1 --target-issue 2 --file "a.ts" --reason "test"

  # Verify other fields are preserved
  jq -e '.session_id == "test1234"' "$SANDBOX/.autopilot/session.json" > /dev/null
  jq -e '.current_phase == 1' "$SANDBOX/.autopilot/session.json" > /dev/null
}
