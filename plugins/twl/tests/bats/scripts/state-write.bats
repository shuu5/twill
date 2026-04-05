#!/usr/bin/env bats
# state-write.bats - unit tests for scripts/state-write.sh

load '../helpers/common'

setup() {
  common_setup
  # Ensure jq is available (real jq, not stubbed)
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: state-write unit test
# ---------------------------------------------------------------------------

# Scenario: issue state init
@test "state-write --init creates issue JSON with status=running" {
  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role worker --init

  assert_success
  assert_output --partial "OK: issue-1.json"

  # Verify file was created
  [ -f "$SANDBOX/.autopilot/issues/issue-1.json" ]

  # Verify status=running
  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "running" ]

  # Verify retry_count=0
  local retry
  retry=$(jq -r '.retry_count' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$retry" = "0" ]
}

# Scenario: reject invalid state transition (done -> running)
@test "state-write rejects done -> running transition" {
  create_issue_json 1 "done"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set status=running

  assert_failure
  assert_output --partial "done"
}

# Scenario: retry limit enforcement
@test "state-write rejects retry when retry_count >= 1" {
  create_issue_json 1 "failed" '.retry_count = 1'

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set status=running

  assert_failure
  assert_output --partial "リトライ上限"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "state-write fails without --type" {
  run python3 -m twl.autopilot.state write \
    --role worker --issue 1 --set status=running

  assert_failure
  assert_output --partial "--type"
}

@test "state-write fails without --role" {
  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --set status=running

  assert_failure
  assert_output --partial "--role"
}

@test "state-write fails with invalid type" {
  run python3 -m twl.autopilot.state write \
    --type bogus --issue 1 --role worker --set status=running

  assert_failure
  assert_output --partial "issue または session"
}

@test "state-write fails with non-numeric issue" {
  run python3 -m twl.autopilot.state write \
    --type issue --issue abc --role worker --init

  assert_failure
  assert_output --partial "正の整数"
}

@test "state-write refuses worker writing to session" {
  run python3 -m twl.autopilot.state write \
    --type session --role worker --set status=running

  assert_failure
  assert_output --partial "Worker"
}

@test "state-write refuses pilot writing non-allowed fields to issue" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set branch=test

  assert_failure
  assert_output --partial "書き込み権限がありません"
}

@test "state-write allows valid running -> merge-ready transition" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set status=merge-ready

  assert_success
  assert_output --partial "OK"

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "merge-ready" ]
}

@test "state-write allows valid running -> failed transition" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set status=failed

  assert_success

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]
}

@test "state-write allows merge-ready -> done transition" {
  create_issue_json 1 "merge-ready"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set status=done

  assert_success

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "done" ]
}

@test "state-write allows failed -> running retry when retry_count=0" {
  create_issue_json 1 "failed" '.retry_count = 0'

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set status=running

  assert_success

  local retry
  retry=$(jq -r '.retry_count' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$retry" = "1" ]
}

@test "state-write rejects invalid transition running -> done" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --set status=done

  assert_failure
  assert_output --partial "不正な状態遷移"
}

@test "state-write --init fails if issue already exists" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role worker --init

  assert_failure
  assert_output --partial "既に存在します"
}

@test "state-write --init rejects pilot for issue init" {
  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role pilot --init

  assert_failure
  assert_output --partial "worker ロールのみ"
}

@test "state-write --init for session type is rejected" {
  run python3 -m twl.autopilot.state write \
    --type session --role pilot --init

  assert_failure
  assert_output --partial "session-create.sh"
}

@test "state-write rejects jq injection in field name" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role worker --set '.foo=bar'

  assert_failure
  assert_output --partial "不正なフィールド名"
}

@test "state-write fails when file does not exist (no --init)" {
  run python3 -m twl.autopilot.state write \
    --type issue --issue 99 --role pilot --set status=failed

  assert_failure
  assert_output --partial "ファイルが存在しません"
}

@test "state-write fails with no --set and no --init" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role worker

  assert_failure
  assert_output --partial "--set"
}

@test "state-write uses atomic write (tmp + mv pattern)" {
  create_issue_json 1 "running"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role worker --set current_step=test

  assert_success

  # After write, no .tmp file should remain
  [ ! -f "$SANDBOX/.autopilot/issues/issue-1.json.tmp" ]

  # File should be valid JSON
  jq '.' "$SANDBOX/.autopilot/issues/issue-1.json" > /dev/null
}

@test "state-write --init sets updated_at field for issue type" {
  run python3 -m twl.autopilot.state write \
    --type issue --issue 5 --role worker --init

  assert_success

  updated_at=$(jq -r '.updated_at' "$SANDBOX/.autopilot/issues/issue-5.json")
  [ "$updated_at" != "null" ]
  [ -n "$updated_at" ]
}

@test "state-write --set updates updated_at for issue type" {
  create_issue_json 6 "running"

  before=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  sleep 1

  run python3 -m twl.autopilot.state write \
    --type issue --issue 6 --role worker --set current_step=test

  assert_success

  updated_at=$(jq -r '.updated_at' "$SANDBOX/.autopilot/issues/issue-6.json")
  [ "$updated_at" != "null" ]
  [ -n "$updated_at" ]
  # updated_at should be >= before
  [[ "$updated_at" > "$before" || "$updated_at" == "$before" ]]
}

@test "state-write --set does not add updated_at for session type" {
  # Create a minimal session.json manually
  mkdir -p "$SANDBOX/.autopilot"
  echo '{"status":"active","current_issue":null}' > "$SANDBOX/.autopilot/session.json"

  run python3 -m twl.autopilot.state write \
    --type session --role pilot --set current_issue=1

  assert_success

  updated_at=$(jq -r '.updated_at' "$SANDBOX/.autopilot/session.json")
  [ "$updated_at" == "null" ]
}
