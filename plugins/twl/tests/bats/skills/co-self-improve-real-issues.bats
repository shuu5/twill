#!/usr/bin/env bats
# co-self-improve-real-issues.bats
# Structural tests for --real-issues routing in co-self-improve SKILL.md (Issue #481)
#
# Verifies that SKILL.md Step 1 contains correct flag routing logic for
# --real-issues mode introduced in Issue C (#479) and Issue D (#480).
#
# Run: bats plugins/twl/tests/bats/skills/co-self-improve-real-issues.bats

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

SKILL_FILE="$REPO_ROOT/skills/co-self-improve/SKILL.md"

# ---------------------------------------------------------------------------
# Case 1: --real-issues フラグ受け入れ
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md mentions --real-issues flag" {
  grep -q '\-\-real-issues' "$SKILL_FILE"
}

@test "co-self-improve: SKILL.md mentions --repo flag for real-issues mode" {
  grep -q '\-\-repo' "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# Case 2: test-project-init への --mode real-issues 委譲
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md Step 1 delegates --mode real-issues to test-project-init" {
  grep -q '\-\-mode real-issues' "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# Case 3: test-project-scenario-load への --real-issues 委譲
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md Step 1 delegates --real-issues to test-project-scenario-load" {
  # The SKILL.md must mention --real-issues in context of scenario-load delegation
  local count
  count=$(grep -c '\-\-real-issues' "$SKILL_FILE")
  [ "$count" -ge 2 ]
}

# ---------------------------------------------------------------------------
# Case 4: AskUserQuestion for ambiguous input
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md contains AskUserQuestion for mode selection" {
  grep -q 'AskUserQuestion' "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# Case 5: co-autopilot spawn path
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md Step 1 mentions co-autopilot spawn" {
  grep -q 'co-autopilot' "$SKILL_FILE"
}

# ---------------------------------------------------------------------------
# Case 6: local mode default behavior preserved
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md retains local mode reference" {
  grep -qi 'local' "$SKILL_FILE"
}
