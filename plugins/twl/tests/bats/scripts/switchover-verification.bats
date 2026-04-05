#!/usr/bin/env bats
# switchover-verification.bats - tests for parallel verification scenarios
#
# Spec: openspec/changes/c-6-switchover/specs/parallel-verification.md
# Requirement: 並行検証チェックリスト

load '../helpers/common'

WORKTREE_ROOT=""

setup() {
  common_setup

  WORKTREE_ROOT="$REPO_ROOT"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: 並行検証チェックリスト
# Scenario: 検証手順の網羅性
# ---------------------------------------------------------------------------

@test "verification-guide: switchover-guide.md exists" {
  [ -f "$WORKTREE_ROOT/docs/switchover-guide.md" ]
}

@test "verification-guide: documents plugin-dir test method" {
  grep -q "plugin-dir" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

@test "verification-guide: documents comparison procedure" {
  # Should describe comparing old vs new plugin behavior
  grep -qi "比較\|comparison\|compare" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

@test "verification-guide: documents twl validate pass criteria" {
  grep -q "twl validate" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

@test "verification-guide: documents twl check pass criteria" {
  grep -q "twl check" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

@test "verification-guide: documents twl audit pass criteria" {
  grep -q "twl audit" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

# ---------------------------------------------------------------------------
# Scenario: plugin-dir による非破壊テスト
# ---------------------------------------------------------------------------

@test "verification: claude --plugin-dir does not require symlink change" {
  # Create a fake plugin dir
  mkdir -p "$SANDBOX/test-plugin"
  touch "$SANDBOX/test-plugin/plugin.json"

  # Verify that using --plugin-dir is a viable path (docs reference it)
  [ -f "$WORKTREE_ROOT/docs/switchover-guide.md" ]
  grep -q "\-\-plugin-dir" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

@test "verification-guide: describes all verification steps in order" {
  # The guide should have numbered steps or clear sequential order
  grep -qE "^[0-9]+\.|^##|ステップ|Step" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "verification-guide: includes rollback instructions" {
  grep -qi "rollback\|ロールバック" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

@test "verification-guide: warns about in-flight sessions" {
  grep -qi "session\|セッション\|in-flight\|autopilot" "$WORKTREE_ROOT/docs/switchover-guide.md"
}

@test "verification-guide: references switchover.sh commands" {
  grep -q "switchover.sh" "$WORKTREE_ROOT/docs/switchover-guide.md"
}
