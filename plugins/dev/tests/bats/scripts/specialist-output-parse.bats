#!/usr/bin/env bats
# specialist-output-parse.bats - unit tests for scripts/specialist-output-parse.sh

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: utility scripts unit test
# ---------------------------------------------------------------------------

@test "specialist-output-parse extracts status and findings from valid output" {
  local input='status: PASS
Some review text
```json
[{"severity":"WARNING","file":"test.ts","line":10,"message":"unused var","confidence":80}]
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "PASS"' > /dev/null
  echo "$output" | jq -e '.findings | length == 1' > /dev/null
  echo "$output" | jq -e '.parse_error == false' > /dev/null
}

@test "specialist-output-parse handles FAIL status" {
  local input='status: FAIL
```json
[{"severity":"CRITICAL","file":"auth.ts","line":5,"message":"SQL injection","confidence":95}]
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "FAIL"' > /dev/null
}

@test "specialist-output-parse handles WARN status" {
  local input='status: WARN
```json
[]
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "specialist-output-parse falls back on missing status" {
  run bash -c "echo 'no status here' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
  echo "$output" | jq -e '.parse_error == true' > /dev/null
  echo "$output" | jq -e '.findings[0].category == "parse-failure"' > /dev/null
}

@test "specialist-output-parse falls back on invalid JSON" {
  local input='status: PASS
```json
{invalid json}
```'

  run bash -c "echo '$input' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.parse_error == true' > /dev/null
}

@test "specialist-output-parse handles empty input" {
  run bash -c "echo '' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.parse_error == true' > /dev/null
  echo "$output" | jq -e '.status == "WARN"' > /dev/null
}

@test "specialist-output-parse handles status with no findings block" {
  run bash -c "echo 'status: PASS' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.status == "PASS"' > /dev/null
  echo "$output" | jq -e '.findings == []' > /dev/null
  echo "$output" | jq -e '.parse_error == false' > /dev/null
}

@test "specialist-output-parse always produces valid JSON" {
  run bash -c "echo 'random garbage \$%^&*' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq '.' > /dev/null
}

@test "specialist-output-parse fallback finding has confidence 50" {
  run bash -c "echo 'no status here' | bash '$SANDBOX/scripts/specialist-output-parse.sh'"

  assert_success
  echo "$output" | jq -e '.findings[0].confidence == 50' > /dev/null
}
