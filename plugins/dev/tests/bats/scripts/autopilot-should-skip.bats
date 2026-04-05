#!/usr/bin/env bats
# autopilot-should-skip.bats - unit tests for scripts/autopilot-should-skip.sh

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# Helper to create a plan.yaml with dependencies
_create_plan_with_deps() {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
session_id: "test1234"
repo_mode: "worktree"
project_dir: "/tmp/test"
phases:
  - phase: 1
    - 1
  - phase: 2
    - 2
dependencies:
  2:
  - 1
EOF
}

_create_plan_multi_deps() {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
session_id: "test1234"
repo_mode: "worktree"
project_dir: "/tmp/test"
phases:
  - phase: 1
    - 1
    - 2
  - phase: 2
    - 3
dependencies:
  3:
  - 1
  - 2
EOF
}

_create_plan_no_deps() {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
session_id: "test1234"
repo_mode: "worktree"
project_dir: "/tmp/test"
phases:
  - phase: 1
    - 1
    - 2
dependencies:
EOF
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-should-skip unit test
# ---------------------------------------------------------------------------

# Note: exit 0 = skip, exit 1 = proceed (execute)

# Scenario: dependent failed -> skip
@test "autopilot-should-skip returns skip=true when dependency is failed" {
  _create_plan_with_deps
  create_issue_json 1 "failed"

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 2

  # exit 0 = skip
  assert_success
}

# Scenario: dependent done -> proceed
@test "autopilot-should-skip returns skip=false when dependency is done" {
  _create_plan_with_deps
  create_issue_json 1 "done"

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 2

  # exit 1 = proceed (all deps done)
  assert_failure
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "autopilot-should-skip proceeds when no dependencies" {
  _create_plan_no_deps

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 1

  # exit 1 = proceed (no deps)
  assert_failure
}

@test "autopilot-should-skip skips when dependency is running (not done)" {
  _create_plan_with_deps
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 2

  # exit 0 = skip (dep not done)
  assert_success
}

@test "autopilot-should-skip skips when dependency state file missing" {
  _create_plan_with_deps
  # No issue-1.json created -- state-read returns empty

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 2

  # exit 0 = skip (empty status != done)
  assert_success
}

@test "autopilot-should-skip skips with one of multiple deps failed" {
  _create_plan_multi_deps
  create_issue_json 1 "done"
  create_issue_json 2 "failed"

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 3

  # exit 0 = skip (one dep not done)
  assert_success
}

@test "autopilot-should-skip proceeds when all multiple deps are done" {
  _create_plan_multi_deps
  create_issue_json 1 "done"
  create_issue_json 2 "done"

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 3

  # exit 1 = proceed
  assert_failure
}

@test "autopilot-should-skip fails with non-numeric issue" {
  _create_plan_no_deps

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" "abc"

  assert_failure
  assert_output --partial "positive integer"
}

@test "autopilot-should-skip fails with missing arguments" {
  run bash "$SANDBOX/scripts/autopilot-should-skip.sh"

  assert_failure
}
