#!/usr/bin/env bats
# merge-gate-execute.bats - unit tests for scripts/merge-gate-execute.sh

load '../helpers/common'

setup() {
  common_setup

  # Default stubs
  stub_command "gh" '
    case "$*" in
      *"pr merge"*)
        exit 0 ;;
      *)
        echo "" ;;
    esac
  '
  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*)
        echo "/tmp/.git/worktrees/test" ;;
      *"worktree list"*)
        echo "" ;;
      *"worktree remove"*)
        exit 0 ;;
      *"push origin --delete"*)
        exit 0 ;;
      *"branch -D"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "tmux" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: merge-gate scripts unit test
# ---------------------------------------------------------------------------

# Scenario: worker rejection for merge-gate-execute
@test "merge-gate-execute requires valid ISSUE environment variable" {
  unset ISSUE

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure
  assert_output --partial "不正なISSUE番号"
}

# ---------------------------------------------------------------------------
# Merge mode tests
# ---------------------------------------------------------------------------

@test "merge-gate-execute performs squash merge on success" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"

  # Track gh pr merge call to verify --squash
  stub_command "gh" '
    if echo "$*" | grep -q "pr merge"; then
      echo "$*" >> $SANDBOX/gh-calls.log
      if echo "$*" | grep -q -- "--squash"; then
        exit 0
      else
        echo "ERROR: expected --squash flag" >&2
        exit 1
      fi
    fi
    exit 0
  '

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  assert_output --partial "マージ + クリーンアップ完了"

  # Verify status changed to done
  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "done" ]

  rm -f $SANDBOX/gh-calls.log
}

@test "merge-gate-execute --reject transitions to failed" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  export FINDING_SUMMARY="Critical bug found"
  export FIX_INSTRUCTIONS="Fix the thing"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject

  assert_success
  assert_output --partial "リジェクト"

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]
}

@test "merge-gate-execute --reject-final transitions to failed" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  export FINDING_SUMMARY="Critical bug again"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh" --reject-final

  assert_success
  assert_output --partial "確定失敗"

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "merge-gate-execute fails with non-numeric PR_NUMBER" {
  export ISSUE=1 PR_NUMBER="abc" BRANCH="feat/1-test"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure
  assert_output --partial "不正なPR_NUMBER"
}

@test "merge-gate-execute fails with invalid BRANCH characters" {
  export ISSUE=1 PR_NUMBER=42 BRANCH='feat/te$t;bad'

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure
  assert_output --partial "不正なBRANCH名"
}

@test "merge-gate-execute handles merge failure gracefully" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"

  stub_command "gh" '
    if echo "$*" | grep -q "pr merge"; then
      echo "merge conflict" >&2
      exit 1
    fi
    exit 0
  '

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "failed" ]
}

@test "merge-gate-execute masks authentication tokens in error output" {
  create_issue_json 1 "merge-ready"
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"

  stub_command "gh" '
    if echo "$*" | grep -q "pr merge"; then
      echo "error: ghp_abc123secret token failed" >&2
      exit 1
    fi
    exit 0
  '

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure
  # Token should be masked
  [[ "$output" != *"ghp_abc123secret"* ]]
}
