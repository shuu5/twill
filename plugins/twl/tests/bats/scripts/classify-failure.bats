#!/usr/bin/env bats
# classify-failure.bats - unit tests for scripts/classify-failure.sh

load '../helpers/common'

setup() {
  common_setup
  # Create snapshot directory
  SNAPSHOT_DIR="$SANDBOX/snapshot"
  mkdir -p "$SNAPSHOT_DIR"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: utility scripts unit test
# ---------------------------------------------------------------------------

# Scenario: failure classification
@test "classify-failure classifies harness error" {
  echo "SKILL.md not found error occurred" > "$SNAPSHOT_DIR/error.md"

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  assert_output --partial "harness"

  # Verify JSON output
  [ -f "$SNAPSHOT_DIR/05.5-failure-classification.json" ]
  jq -e '.classification == "harness"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

@test "classify-failure classifies code error" {
  echo "TypeError: undefined is not a function" > "$SNAPSHOT_DIR/error.md"

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  assert_output --partial "code"

  jq -e '.classification == "code"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

@test "classify-failure returns unknown for ambiguous errors" {
  echo "Something went wrong" > "$SNAPSHOT_DIR/error.md"

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  assert_output --partial "unknown"

  jq -e '.classification == "unknown"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
  jq -e '.confidence == 30' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "classify-failure fails without snapshot-dir argument" {
  run bash "$SANDBOX/scripts/classify-failure.sh"

  assert_failure
}

@test "classify-failure fails with non-existent snapshot-dir" {
  run bash "$SANDBOX/scripts/classify-failure.sh" "$SANDBOX/nonexistent"

  assert_failure
  assert_output --partial "見つかりません"
}

@test "classify-failure detects specialist spawn error" {
  echo "specialist not spawn error" > "$SNAPSHOT_DIR/error.md"

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  jq -e '.classification == "harness"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

@test "classify-failure detects hook execution error" {
  echo "PreToolUse hook error in settings.json" > "$SNAPSHOT_DIR/error.md"

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  jq -e '.classification == "harness"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

@test "classify-failure detects test assertion failure as code" {
  echo "AssertionError: expect(2).toBe(3)" > "$SNAPSHOT_DIR/error.md"

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  jq -e '.classification == "code"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

@test "classify-failure confidence capped at 100" {
  # Multiple harness patterns to push score high
  cat > "$SNAPSHOT_DIR/error.md" <<'EOF'
SKILL.md parse error
specialist not spawn
PreToolUse hook error
autopilot error occurred
EOF

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  local conf
  conf=$(jq -r '.confidence' "$SNAPSHOT_DIR/05.5-failure-classification.json")
  [ "$conf" -le 100 ]
}

@test "classify-failure prefers harness when scores are equal" {
  # Both harness and code patterns (harness: SKILL.md +25, specialist +25 = 50; code: TypeError +30)
  # harness_score >= code_score, so harness should win
  cat > "$SNAPSHOT_DIR/error.md" <<'EOF'
SKILL.md error
specialist not spawn
TypeError: undefined
EOF

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  # Harness should win on tie
  jq -e '.classification == "harness"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

@test "classify-failure produces valid JSON output" {
  echo "some error" > "$SNAPSHOT_DIR/error.md"

  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  jq -e '.classification' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
  jq -e '.confidence | type == "number"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
  jq -e '.evidence | type == "array"' "$SNAPSHOT_DIR/05.5-failure-classification.json" > /dev/null
}

@test "classify-failure handles empty snapshot directory" {
  run bash "$SANDBOX/scripts/classify-failure.sh" "$SNAPSHOT_DIR"

  assert_success
  assert_output --partial "unknown"
}
