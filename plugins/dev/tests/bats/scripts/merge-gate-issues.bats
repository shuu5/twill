#!/usr/bin/env bats
# merge-gate-issues.bats - unit tests for scripts/merge-gate-issues.sh

load '../helpers/common'

setup() {
  common_setup
  export ISSUE=1
  export PR_NUMBER=42

  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo "shuu5/test-repo" ;;
      *"issue create"*)
        echo "https://github.com/shuu5/test-repo/issues/100" ;;
      *)
        echo "" ;;
    esac
  '
  stub_command "git" '
    case "$*" in
      *"remote get-url"*)
        echo "https://github.com/shuu5/test-repo.git" ;;
      *)
        exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: merge-gate scripts unit test
# ---------------------------------------------------------------------------

@test "merge-gate-issues outputs eval-able TECH_DEBT_ISSUES and SELF_IMPROVE_ISSUES" {
  # No findings files -- should output empty variables
  run bash "$SANDBOX/scripts/merge-gate-issues.sh"

  assert_success
  assert_output --partial "TECH_DEBT_ISSUES="
  assert_output --partial "SELF_IMPROVE_ISSUES="
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "merge-gate-issues fails without ISSUE env var" {
  unset ISSUE

  run bash "$SANDBOX/scripts/merge-gate-issues.sh"

  assert_failure
  assert_output --partial "不正なISSUE番号"
}

@test "merge-gate-issues fails without PR_NUMBER env var" {
  unset PR_NUMBER

  run bash "$SANDBOX/scripts/merge-gate-issues.sh"

  assert_failure
  assert_output --partial "不正なPR_NUMBER"
}

@test "merge-gate-issues creates tech-debt issues from findings file" {
  local findings_file="/tmp/merge-gate-findings-test-$$.json"
  cat > "$findings_file" <<'JSON'
[{"message":"unused import","severity":"low","file":"src/main.ts","line":"10","category":"lint"}]
JSON
  export FINDINGS_FILE="$findings_file"

  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo "shuu5/test-repo" ;;
      *"issue create"*)
        echo "https://github.com/shuu5/test-repo/issues/101" ;;
      *)
        echo "" ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-issues.sh"

  assert_success
  assert_output --partial "TECH_DEBT_ISSUES="
  assert_output --partial "issues/101"

  rm -f "$findings_file"
}

@test "merge-gate-issues rejects FINDINGS_FILE outside /tmp/" {
  export FINDINGS_FILE="/etc/passwd"

  run bash "$SANDBOX/scripts/merge-gate-issues.sh"

  assert_success
  # Should warn and skip, not fail
  assert_output --partial "TECH_DEBT_ISSUES=''"
}

@test "merge-gate-issues rejects SELF_IMPROVE_FILE outside /tmp/" {
  export SELF_IMPROVE_FILE="/etc/passwd"

  run bash "$SANDBOX/scripts/merge-gate-issues.sh"

  assert_success
  assert_output --partial "SELF_IMPROVE_ISSUES=''"
}

@test "merge-gate-issues validates DEV_REPO format" {
  stub_command "gh" '
    case "$*" in
      *"pr view"*)
        echo "invalid-repo-format" ;;
      *)
        echo "" ;;
    esac
  '
  stub_command "git" '
    echo "invalid" ;;
  '

  run bash "$SANDBOX/scripts/merge-gate-issues.sh"

  assert_success
  # Should continue without creating issues
}
