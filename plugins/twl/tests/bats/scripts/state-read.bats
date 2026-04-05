#!/usr/bin/env bats
# state-read.bats - unit tests for scripts/state-read.sh

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: state-read unit test
# ---------------------------------------------------------------------------

# Scenario: single field read
@test "state-read returns single field value" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/state-read.sh" \
    --type issue --issue 1 --field status

  assert_success
  assert_output "running"
}

# Scenario: non-existent file returns empty string and exit 0
@test "state-read returns empty string for non-existent file" {
  run bash "$SANDBOX/scripts/state-read.sh" \
    --type issue --issue 99 --field status

  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "state-read returns full JSON without --field" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/state-read.sh" \
    --type issue --issue 1

  assert_success
  # Output should be valid JSON
  echo "$output" | jq '.' > /dev/null
  # Should contain status field
  echo "$output" | jq -e '.status == "running"' > /dev/null
}

@test "state-read fails without --type" {
  run bash "$SANDBOX/scripts/state-read.sh" --issue 1 --field status

  assert_failure
  assert_output --partial "--type"
}

@test "state-read fails with invalid type" {
  run bash "$SANDBOX/scripts/state-read.sh" \
    --type bogus --issue 1 --field status

  assert_failure
  assert_output --partial "issue または session"
}

@test "state-read fails without --issue for type=issue" {
  run bash "$SANDBOX/scripts/state-read.sh" \
    --type issue --field status

  assert_failure
  assert_output --partial "--issue"
}

@test "state-read fails with non-numeric issue" {
  run bash "$SANDBOX/scripts/state-read.sh" \
    --type issue --issue abc --field status

  assert_failure
  assert_output --partial "正の整数"
}

@test "state-read rejects jq injection in field name" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/state-read.sh" \
    --type issue --issue 1 --field '.foo'

  assert_failure
  assert_output --partial "不正なフィールド名"
}

@test "state-read returns empty for non-existent field" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/state-read.sh" \
    --type issue --issue 1 --field nonexistent

  assert_success
  assert_output ""
}

@test "state-read can read session.json" {
  create_session_json

  run bash "$SANDBOX/scripts/state-read.sh" \
    --type session --field session_id

  assert_success
  assert_output "test1234"
}

@test "state-read returns empty string for non-existent session.json" {
  # No session.json exists in sandbox

  run bash "$SANDBOX/scripts/state-read.sh" \
    --type session --field session_id

  assert_success
  assert_output ""
}

@test "state-read --help shows usage" {
  run bash "$SANDBOX/scripts/state-read.sh" --help

  assert_success
  assert_output --partial "Usage:"
}
