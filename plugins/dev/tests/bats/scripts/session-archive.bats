#!/usr/bin/env bats
# session-archive.bats - unit tests for scripts/session-archive.sh

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

@test "session-archive moves session.json and issues to archive" {
  create_session_json
  create_issue_json 1 "done"
  create_issue_json 2 "done"

  run bash "$SANDBOX/scripts/session-archive.sh"

  assert_success
  assert_output --partial "アーカイブしました"

  # session.json should be moved
  [ ! -f "$SANDBOX/.autopilot/session.json" ]

  # Archive should contain session.json and issues
  [ -f "$SANDBOX/.autopilot/archive/test1234/session.json" ]
  [ -f "$SANDBOX/.autopilot/archive/test1234/issues/issue-1.json" ]
  [ -f "$SANDBOX/.autopilot/archive/test1234/issues/issue-2.json" ]

  # Original issues should be moved
  [ ! -f "$SANDBOX/.autopilot/issues/issue-1.json" ]
  [ ! -f "$SANDBOX/.autopilot/issues/issue-2.json" ]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "session-archive fails when session.json does not exist" {
  rm -f "$SANDBOX/.autopilot/session.json"

  run bash "$SANDBOX/scripts/session-archive.sh"

  assert_failure
  assert_output --partial "session.json が存在しません"
}

@test "session-archive works with no issue files" {
  create_session_json
  # No issue files

  run bash "$SANDBOX/scripts/session-archive.sh"

  assert_success
  [ -f "$SANDBOX/.autopilot/archive/test1234/session.json" ]
}

@test "session-archive rejects invalid session_id (path traversal)" {
  mkdir -p "$SANDBOX/.autopilot"
  echo '{"session_id": "../../../etc"}' > "$SANDBOX/.autopilot/session.json"

  run bash "$SANDBOX/scripts/session-archive.sh"

  assert_failure
  assert_output --partial "不正な session_id"
}
