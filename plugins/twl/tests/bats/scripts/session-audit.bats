#!/usr/bin/env bats
# session-audit.bats - unit tests for python3 -m twl.autopilot.session audit

load '../helpers/common'

setup() {
  common_setup
  # Allow any path for testing
  export SESSION_AUDIT_ALLOW_ANY_PATH=1
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: session-audit
# ---------------------------------------------------------------------------

@test "session-audit fails without argument" {
  run python3 -m twl.autopilot.session audit

  assert_failure
  assert_output --partial "Usage"
}

@test "session-audit fails with non-existent file" {
  run python3 -m twl.autopilot.session audit "$SANDBOX/nonexistent.jsonl"

  assert_failure
  assert_output --partial "not found"
}

@test "session-audit fails with empty file" {
  touch "$SANDBOX/empty.jsonl"

  run python3 -m twl.autopilot.session audit "$SANDBOX/empty.jsonl"

  assert_failure
  assert_output --partial "empty"
}

@test "session-audit processes valid JSONL" {
  cat > "$SANDBOX/test.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"test123","timestamp":"2024-01-01T00:00:00Z","message":{"content":[{"type":"text","text":"Hello"}]}}
{"type":"assistant","sessionId":"test123","timestamp":"2024-01-01T00:01:00Z","message":{"content":[{"type":"tool_use","name":"Bash","id":"t1","input":{"command":"ls"}}]}}
{"type":"user","timestamp":"2024-01-01T00:01:01Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"file1.txt"}]}}
JSONL

  run python3 -m twl.autopilot.session audit "$SANDBOX/test.jsonl"

  assert_success
  # Should contain metadata entry
  echo "$output" | head -1 | jq -e '.entry_type == "metadata"' > /dev/null
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "session-audit rejects path outside allowed prefix (without override)" {
  unset SESSION_AUDIT_ALLOW_ANY_PATH

  cat > "$SANDBOX/test.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"test","timestamp":"2024-01-01T00:00:00Z","message":{"content":[{"type":"text","text":"test"}]}}
JSONL

  run python3 -m twl.autopilot.session audit "$SANDBOX/test.jsonl"

  assert_failure
  assert_output --partial "Path must be under"
}

@test "session-audit handles file with invalid JSON lines" {
  cat > "$SANDBOX/test.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"test","timestamp":"2024-01-01T00:00:00Z","message":{"content":[{"type":"text","text":"valid"}]}}
this is not json
{"type":"assistant","sessionId":"test","timestamp":"2024-01-01T00:00:01Z","message":{"content":[{"type":"text","text":"also valid"}]}}
JSONL

  run python3 -m twl.autopilot.session audit "$SANDBOX/test.jsonl"

  assert_success
  # Should skip invalid lines and process valid ones
  echo "$output" | head -1 | jq -e '.entry_type == "metadata"' > /dev/null
}

@test "session-audit extracts tool calls correctly" {
  cat > "$SANDBOX/test.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"test","timestamp":"2024-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Read","id":"t1","input":{"file_path":"/tmp/test.txt"}}]}}
{"type":"user","timestamp":"2024-01-01T00:00:01Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"file content"}]}}
JSONL

  run python3 -m twl.autopilot.session audit "$SANDBOX/test.jsonl"

  assert_success
  # Should contain tool_call entry
  echo "$output" | grep "tool_call" | jq -e '.tool_name == "Read"' > /dev/null
}

@test "session-audit limits text to configured lengths" {
  # Create a very long text entry
  local long_text
  long_text=$(python3 -c "print('x' * 500)" 2>/dev/null || printf '%500s' | tr ' ' 'x')
  cat > "$SANDBOX/test.jsonl" <<JSONL
{"type":"assistant","sessionId":"test","timestamp":"2024-01-01T00:00:00Z","message":{"content":[{"type":"text","text":"$long_text"}]}}
JSONL

  run python3 -m twl.autopilot.session audit "$SANDBOX/test.jsonl"

  assert_success
  # ai_text should be truncated to AI_TEXT_LIMIT (200)
  local text_len
  text_len=$(echo "$output" | grep "ai_text" | jq -r '.text | length')
  [ "$text_len" -le 200 ]
}

@test "session-audit unreadable file" {
  touch "$SANDBOX/unreadable.jsonl"
  chmod 000 "$SANDBOX/unreadable.jsonl"

  run python3 -m twl.autopilot.session audit "$SANDBOX/unreadable.jsonl"

  assert_failure

  chmod 644 "$SANDBOX/unreadable.jsonl" 2>/dev/null || true
}
