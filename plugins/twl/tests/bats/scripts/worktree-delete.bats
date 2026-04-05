#!/usr/bin/env bats
# worktree-delete.bats - unit tests for scripts/worktree-delete.sh

load '../helpers/common'

setup() {
  common_setup
  # stub git operations
  stub_command "git" '
    case "$*" in
      *"worktree remove"*) exit 0 ;;
      *"worktree list"*)   echo "" ;;
      *"branch"*)          exit 0 ;;
      *)                   exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: worktree-create / worktree-delete unit test
# ---------------------------------------------------------------------------

# Scenario: worker rejection for worktree-delete
@test "worktree-delete rejects execution from worktrees/ directory" {
  # Simulate CWD inside worktrees/
  mkdir -p "$SANDBOX/worktrees/feat/test-branch"
  cd "$SANDBOX/worktrees/feat/test-branch"

  run bash "$REPO_ROOT/scripts/worktree-delete.sh" "feat/test-branch"

  assert_failure
  assert_output --partial "Worker"
  assert_output --partial "不変条件 B"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "worktree-delete shows help with no arguments" {
  run bash "$REPO_ROOT/scripts/worktree-delete.sh"

  assert_success
  assert_output --partial "Usage:"
}

@test "worktree-delete shows help with -h" {
  run bash "$REPO_ROOT/scripts/worktree-delete.sh" -h

  assert_success
  assert_output --partial "Usage:"
}

@test "worktree-delete rejects path traversal in branch name" {
  run bash "$REPO_ROOT/scripts/worktree-delete.sh" "../../../etc/passwd"

  assert_failure
  assert_output --partial "パストラバーサル"
}

@test "worktree-delete rejects absolute path as branch name" {
  run bash "$REPO_ROOT/scripts/worktree-delete.sh" "/etc/passwd"

  assert_failure
  assert_output --partial "パストラバーサル"
}

@test "worktree-delete rejects branch name with .." {
  run bash "$REPO_ROOT/scripts/worktree-delete.sh" "feat/../main"

  assert_failure
  assert_output --partial "パストラバーサル"
}

@test "worktree-delete accepts valid branch name characters" {
  # Stub CWD to be in main/ (not worktrees/)
  cd "$SANDBOX"
  touch "$SANDBOX/.git"  # Simulate worktree pointer

  # This will fail at bare repo detection, which is expected
  # We just want to confirm it passes input validation
  run bash "$REPO_ROOT/scripts/worktree-delete.sh" "feat/12-test"

  # Should NOT fail on input validation
  [[ "$output" != *"パストラバーサル"* ]]
  [[ "$output" != *"不正なブランチ名"* ]]
}
