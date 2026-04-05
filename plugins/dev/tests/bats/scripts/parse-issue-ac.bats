#!/usr/bin/env bats
# parse-issue-ac.bats - unit tests for scripts/parse-issue-ac.sh

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

# Scenario: AC parse
@test "parse-issue-ac extracts checkbox AC items" {
  stub_command "gh" '
    case "$*" in
      *"issues/1"*"body"*)
        cat <<BODY
## 受け入れ基準
- [ ] First criterion
- [ ] Second criterion
- [x] Third criterion (done)
## Other section
BODY
        ;;
      *"issues/1"*"comments"*)
        echo "[]" ;;
      *"issues/1"*)
        echo "{\"body\": \"test\", \"pull_request\": null}" ;;
      *)
        echo "[]" ;;
    esac
  '

  run bash "$SANDBOX/scripts/parse-issue-ac.sh" 1

  assert_success
  assert_line --index 0 --partial "1. First criterion"
  assert_line --index 1 --partial "2. Second criterion"
  assert_line --index 2 --partial "3. Third criterion"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "parse-issue-ac fails without issue number" {
  run bash "$SANDBOX/scripts/parse-issue-ac.sh"

  assert_failure
  assert_output --partial "Usage"
}

@test "parse-issue-ac rejects non-numeric issue number" {
  run bash "$SANDBOX/scripts/parse-issue-ac.sh" "abc"

  assert_failure
  assert_output --partial "整数"
}

@test "parse-issue-ac exits 2 when no AC section found" {
  stub_command "gh" '
    case "$*" in
      *"issues/1"*"body"*)
        echo "No AC section here" ;;
      *"issues/1"*"comments"*)
        echo "[]" ;;
      *"issues/1"*)
        echo "{\"body\": \"test\", \"pull_request\": null}" ;;
      *)
        echo "[]" ;;
    esac
  '

  run bash "$SANDBOX/scripts/parse-issue-ac.sh" 1

  assert_failure
  [ "$status" -eq 2 ]
}

@test "parse-issue-ac exits 2 when AC section has no checkboxes" {
  stub_command "gh" '
    case "$*" in
      *"issues/1"*"body"*)
        cat <<BODY
## 受け入れ基準
Some text without checkboxes
BODY
        ;;
      *"issues/1"*"comments"*)
        echo "[]" ;;
      *"issues/1"*)
        echo "{\"body\": \"test\", \"pull_request\": null}" ;;
      *)
        echo "[]" ;;
    esac
  '

  run bash "$SANDBOX/scripts/parse-issue-ac.sh" 1

  assert_failure
  [ "$status" -eq 2 ]
}

@test "parse-issue-ac includes AC from comments" {
  # Note: comments pattern must come BEFORE body pattern because the
  # gh api comments call includes "body" in its --jq arg, which would
  # match *"body"* if checked first.
  stub_command "gh" '
    case "$*" in
      *"issues/1/comments"*)
        echo "- [ ] From comment" ;;
      *"issues/1"*".body"*)
        cat <<BODY
## 受け入れ基準
- [ ] From body
## Other section
Some other content
BODY
        ;;
      *"issues/1"*"pull_request"*)
        echo "" ;;
      *"issues/1"*)
        echo "{\"body\": \"test\", \"pull_request\": null}" ;;
      *)
        echo "" ;;
    esac
  '

  run bash "$SANDBOX/scripts/parse-issue-ac.sh" 1

  assert_success
  assert_output --partial "1. From body"
  assert_output --partial "2. From comment"
}

@test "parse-issue-ac fails when gh returns empty body" {
  stub_command "gh" '
    case "$*" in
      *"issues/1"*"body"*)
        echo "" ;;
      *"issues/1"*"comments"*)
        echo "[]" ;;
      *"issues/1"*)
        echo "" ;;
      *)
        echo "" ;;
    esac
  '

  run bash "$SANDBOX/scripts/parse-issue-ac.sh" 1

  assert_failure
}
