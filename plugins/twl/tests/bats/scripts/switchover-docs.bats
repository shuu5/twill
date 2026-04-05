#!/usr/bin/env bats
# switchover-docs.bats - tests for design decisions documentation
#
# Spec: openspec/changes/c-6-switchover/specs/design-decisions-doc.md
# Requirement: 設計経緯転記ドキュメント

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
# Requirement: 設計経緯転記ドキュメント
# Scenario: 必須転記項目の網羅
# ---------------------------------------------------------------------------

@test "design-decisions: document exists" {
  [ -f "$WORKTREE_ROOT/docs/design-decisions.md" ]
}

@test "design-decisions: contains merge-gate integration rationale" {
  grep -qi "merge-gate\|マージゲート" "$WORKTREE_ROOT/docs/design-decisions.md"
}

@test "design-decisions: contains deps.yaml conflict control explanation" {
  grep -qi "deps.yaml.*競合\|conflict.*phase\|Phase.*分離" "$WORKTREE_ROOT/docs/design-decisions.md"
}

@test "design-decisions: contains autopilot invariants documentation" {
  grep -qi "autopilot.*不変\|autopilot.*invariant" "$WORKTREE_ROOT/docs/design-decisions.md"
}

@test "design-decisions: all three required items present in same file" {
  local merge_gate deps_yaml autopilot
  merge_gate=$(grep -ci "merge-gate" "$WORKTREE_ROOT/docs/design-decisions.md" || true)
  deps_yaml=$(grep -ci "deps.yaml" "$WORKTREE_ROOT/docs/design-decisions.md" || true)
  autopilot=$(grep -ci "autopilot" "$WORKTREE_ROOT/docs/design-decisions.md" || true)

  [ "$merge_gate" -ge 1 ]
  [ "$deps_yaml" -ge 1 ]
  [ "$autopilot" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Scenario: 旧プラグインからの追跡可能性
# ---------------------------------------------------------------------------

@test "design-decisions: merge-gate entry has source reference" {
  # Should reference the original SKILL.md or file it came from
  grep -A5 -i "merge-gate" "$WORKTREE_ROOT/docs/design-decisions.md" | grep -qi "SKILL.md\|出典\|source\|転記元\|claude-plugin-dev"
}

@test "design-decisions: deps.yaml entry has source reference" {
  grep -A5 -i "deps.yaml" "$WORKTREE_ROOT/docs/design-decisions.md" | grep -qi "SKILL.md\|出典\|source\|転記元\|claude-plugin-dev"
}

@test "design-decisions: autopilot entry has source reference" {
  grep -A5 -i "autopilot.*不変\|autopilot.*invariant" "$WORKTREE_ROOT/docs/design-decisions.md" | grep -qi "SKILL.md\|出典\|source\|転記元\|claude-plugin-dev"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "design-decisions: entries have headings or clear structure" {
  # Each entry should be findable via heading
  local heading_count
  heading_count=$(grep -cE "^#{1,4} " "$WORKTREE_ROOT/docs/design-decisions.md" || true)
  [ "$heading_count" -ge 3 ]
}

@test "design-decisions: no placeholder text remains" {
  ! grep -qi "TODO\|FIXME\|TBD\|placeholder" "$WORKTREE_ROOT/docs/design-decisions.md"
}

@test "design-decisions: file is valid markdown (no unclosed code blocks)" {
  # Count opening and closing triple backticks - should be even
  local backtick_count
  backtick_count=$(grep -c '```' "$WORKTREE_ROOT/docs/design-decisions.md" || true)
  [ $((backtick_count % 2)) -eq 0 ]
}

@test "design-decisions: source references point to real filenames" {
  # Extract referenced filenames and verify they look legitimate
  # (not checking they exist in old repo, but that they have file extensions)
  local refs
  refs=$(grep -oE "[A-Za-z_-]+\.(md|yaml|sh)" "$WORKTREE_ROOT/docs/design-decisions.md" | head -5)
  [ -n "$refs" ]
}
