#!/usr/bin/env bats
# tech-stack-detect.bats - unit tests for scripts/tech-stack-detect.sh

load '../helpers/common'

setup() {
  common_setup

  # Create a git repo in sandbox
  git init "$SANDBOX/test-project" 2>/dev/null
  cd "$SANDBOX/test-project"
  git commit --allow-empty -m "initial" 2>/dev/null

  mkdir -p "$SANDBOX/test-project/scripts"
  cp "$REPO_ROOT/scripts/tech-stack-detect.sh" "$SANDBOX/test-project/scripts/"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: utility scripts unit test
# ---------------------------------------------------------------------------

@test "tech-stack-detect outputs nothing for unrecognized files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'README.md' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output ""
}

@test "tech-stack-detect detects R files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'analysis.R' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-r-reviewer"
}

@test "tech-stack-detect detects Rmd files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'report.Rmd' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-r-reviewer"
}

@test "tech-stack-detect detects supabase migrations" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'supabase/migrations/001.sql' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-supabase-migration-checker"
}

@test "tech-stack-detect detects E2E test files" {
  cd "$SANDBOX/test-project"
  run bash -c "echo 'e2e/login.spec.ts' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-e2e-reviewer"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "tech-stack-detect handles empty input" {
  cd "$SANDBOX/test-project"
  run bash -c "echo '' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output ""
}

@test "tech-stack-detect handles multiple file types" {
  cd "$SANDBOX/test-project"
  run bash -c "printf 'analysis.R\nsupabase/migrations/001.sql\n' | bash scripts/tech-stack-detect.sh"

  assert_success
  assert_output --partial "worker-r-reviewer"
  assert_output --partial "worker-supabase-migration-checker"
}

@test "tech-stack-detect tsx requires next.config for nextjs detection" {
  cd "$SANDBOX/test-project"

  # Without next.config.* -- should not detect nextjs
  run bash -c "echo 'app.tsx' | bash scripts/tech-stack-detect.sh"
  [[ "$output" != *"worker-nextjs-reviewer"* ]]

  # With next.config.js -- should detect
  touch next.config.js
  run bash -c "echo 'app.tsx' | bash scripts/tech-stack-detect.sh"
  assert_output --partial "worker-nextjs-reviewer"
  rm -f next.config.js
}

@test "tech-stack-detect does not duplicate specialists" {
  cd "$SANDBOX/test-project"
  run bash -c "printf 'a.R\nb.R\nc.Rmd\n' | bash scripts/tech-stack-detect.sh"

  assert_success
  # Should only appear once
  local count
  count=$(echo "$output" | grep -c "worker-r-reviewer" || true)
  [ "$count" -eq 1 ]
}
