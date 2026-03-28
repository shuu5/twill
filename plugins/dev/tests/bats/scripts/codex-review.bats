#!/usr/bin/env bats
# codex-review.bats - unit tests for scripts/codex-review.sh

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: codex-review
# ---------------------------------------------------------------------------

@test "codex-review skips when codex is not installed" {
  # Restrict PATH so codex is not found (only stub bin + essential system dirs)
  export PATH="$STUB_BIN:/usr/local/bin:/usr/bin:/bin"

  run bash "$SANDBOX/scripts/codex-review.sh" main /dev/stdout

  assert_success
  assert_output --partial "codex CLI not installed"
}

@test "codex-review skips when CODEX_API_KEY is not set" {
  stub_command "codex" 'echo "codex is here"'
  unset CODEX_API_KEY

  run bash "$SANDBOX/scripts/codex-review.sh" main /dev/stdout

  assert_success
  assert_output --partial "CODEX_API_KEY not set"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "codex-review rejects invalid branch name (injection)" {
  stub_command "codex" 'exit 0'
  export CODEX_API_KEY="test"

  run bash "$SANDBOX/scripts/codex-review.sh" 'main;rm -rf /' /dev/stdout

  assert_failure
  assert_output --partial "invalid BASE_BRANCH"
}

@test "codex-review accepts valid branch names" {
  stub_command "codex" 'echo "no issues"'
  export CODEX_API_KEY="test"

  # These should pass validation (may fail at codex exec but that's fine)
  for branch in "main" "origin/main" "feat/test-branch" "v1.0.0~1"; do
    run bash "$SANDBOX/scripts/codex-review.sh" "$branch" /dev/stdout
    [[ "$output" != *"invalid BASE_BRANCH"* ]]
  done
}

@test "codex-review creates output directory if needed" {
  stub_command "codex" 'echo "review output"'
  export CODEX_API_KEY="test"

  local output_file="$SANDBOX/output/nested/review.md"

  run bash "$SANDBOX/scripts/codex-review.sh" main "$output_file"

  # Should create the directory
  [ -d "$SANDBOX/output/nested" ]
}

@test "codex-review defaults to main and /dev/stdout" {
  # Restrict PATH so codex is not found -- should exit 0 with skip message
  export PATH="$STUB_BIN:/usr/local/bin:/usr/bin:/bin"

  run bash "$SANDBOX/scripts/codex-review.sh"

  assert_success
  assert_output --partial "codex CLI not installed"
}
