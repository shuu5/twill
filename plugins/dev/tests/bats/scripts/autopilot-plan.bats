#!/usr/bin/env bats
# autopilot-plan.bats - unit tests for scripts/autopilot-plan.sh

load '../helpers/common'

setup() {
  common_setup
  # stub uuidgen for deterministic session ID
  stub_command "uuidgen" 'echo "12345678-abcd-efgh-ijkl-123456789012"'
  # stub gh to return valid issue and empty body/comments
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json body"*)
        echo "" ;;
      *"api"*"issues"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-plan unit test
# ---------------------------------------------------------------------------

# Scenario: linear dependency Phase split (A -> B -> C)
@test "autopilot-plan --explicit creates linear phases" {
  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "1 → 2 → 3" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  assert_output --partial "Phases: 3"

  # Verify plan.yaml was created
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]

  # Verify phase structure
  grep -q "phase: 1" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "phase: 2" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "phase: 3" "$SANDBOX/.autopilot/plan.yaml"
}

# Scenario: parallel issues in same phase
@test "autopilot-plan --explicit puts parallel issues in same phase" {
  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "1,2 → 3" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  assert_output --partial "Phases: 2"
  assert_output --partial "Issues: 3"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "autopilot-plan fails without required arguments" {
  run bash "$SANDBOX/scripts/autopilot-plan.sh"

  assert_failure
  assert_output --partial "Usage"
}

@test "autopilot-plan fails with unknown argument" {
  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --invalid-arg

  assert_failure
}

@test "autopilot-plan --explicit with single issue" {
  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "1" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  assert_output --partial "Phases: 1"
  assert_output --partial "Issues: 1"
}

@test "autopilot-plan --issues with independent issues creates single phase" {
  # gh stubs: no dependency keywords in body
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json body"*)
        echo "No dependencies here" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "1 2 3" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  assert_output --partial "Phases: 1"
}

@test "autopilot-plan --issues detects dependency keywords" {
  # Issue 2 depends on Issue 1 via "depends on #1"
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*2*"--json body"*)
        echo "This depends on #1" ;;
      *"issue view"*"--json body"*)
        echo "No deps" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "1 2" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  assert_output --partial "Phases: 2"
}

@test "autopilot-plan --issues detects circular dependency" {
  # Issue 1 depends on 2, Issue 2 depends on 1
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*1*"--json body"*)
        echo "depends on #2" ;;
      *"issue view"*2*"--json body"*)
        echo "depends on #1" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "1 2" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_failure
  assert_output --partial "循環依存"
}

@test "autopilot-plan creates .autopilot directory if missing" {
  rmdir "$SANDBOX/.autopilot/archive" "$SANDBOX/.autopilot/issues" "$SANDBOX/.autopilot" 2>/dev/null || true

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "1" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  [ -d "$SANDBOX/.autopilot" ]
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
}
