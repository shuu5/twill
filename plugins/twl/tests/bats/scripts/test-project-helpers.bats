#!/usr/bin/env bats
# test-project-helpers.bats - test-project-{init,reset,scenario-load} helper tests
# Uses real git operations in sandbox (no git mock), gh only stubbed.

load '../helpers/common'

setup() {
  common_setup

  # Create a simple git repo that simulates the twill bare-repo layout
  # We use a normal repo (not bare) since worktree operations need a working tree root
  mkdir -p "$SANDBOX/bare-repo"
  git init "$SANDBOX/bare-repo" 2>/dev/null
  cd "$SANDBOX/bare-repo"
  git commit --allow-empty -m "initial main commit" 2>/dev/null

  # Set up worktrees/ directory
  mkdir -p "$SANDBOX/bare-repo/worktrees"

  # Set up test-fixtures/minimal-plugin/ with realistic content
  mkdir -p "$SANDBOX/bare-repo/test-fixtures/minimal-plugin/commands"
  mkdir -p "$SANDBOX/bare-repo/test-fixtures/minimal-plugin/scripts"
  printf '#!/bin/bash\necho "hello"\n' > "$SANDBOX/bare-repo/test-fixtures/minimal-plugin/scripts/helper.sh"
  cat > "$SANDBOX/bare-repo/test-fixtures/minimal-plugin/commands/do-task.md" <<'EOF'
---
type: atomic
---
# do-task
Test task.
EOF
  cat > "$SANDBOX/bare-repo/test-fixtures/minimal-plugin/deps.yaml" <<'EOF'
version: "3.0"
plugin: minimal-plugin
commands:
  do-task:
    type: atomic
    path: commands/do-task.md
EOF

  BARE_ROOT="$SANDBOX/bare-repo"
  export BARE_ROOT
}

teardown() {
  # Remove worktrees before cleaning sandbox (avoid git lock issues)
  if git -C "$BARE_ROOT" worktree list 2>/dev/null | grep -q "test-target"; then
    git -C "$BARE_ROOT" worktree remove --force "$BARE_ROOT/worktrees/test-target" 2>/dev/null || true
  fi
  git -C "$BARE_ROOT" branch -D test-target/main 2>/dev/null || true
  git -C "$BARE_ROOT" tag -d test-target/initial 2>/dev/null || true
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: create test-target worktree (shared init logic for reset/scenario tests)
# ---------------------------------------------------------------------------
_init_test_target() {
  local repo="$BARE_ROOT"
  local wt_path="$BARE_ROOT/worktrees/test-target"

  # Create orphan branch from empty tree
  local empty_tree
  empty_tree=$(git -C "$repo" hash-object -t tree --stdin </dev/null)
  local initial_commit
  initial_commit=$(git -C "$repo" commit-tree "$empty_tree" -m "test-target: initial empty commit")
  git -C "$repo" update-ref refs/heads/test-target/main "$initial_commit"

  # Add worktree
  git -C "$repo" worktree add "$wt_path" test-target/main 2>/dev/null

  # Copy content
  cp -r "$BARE_ROOT/test-fixtures/minimal-plugin/"* "$wt_path/"
  mkdir -p "$wt_path/.test-target/issues"

  # Initial commit + tag
  cd "$wt_path"
  git add -A
  git commit -m "test-target: initial scaffold" 2>/dev/null
  git tag test-target/initial
}

# ---------------------------------------------------------------------------
# init: normal case
# ---------------------------------------------------------------------------
@test "init: test-target worktree is created with orphan branch" {
  _init_test_target

  # Verify worktree exists in listing
  run git -C "$BARE_ROOT" worktree list
  assert_output --partial "test-target"

  # Verify orphan: no common ancestor between main and test-target/main
  cd "$BARE_ROOT"
  run git merge-base HEAD test-target/main 2>&1
  assert_failure

  # Verify content was copied
  [[ -f "$BARE_ROOT/worktrees/test-target/deps.yaml" ]]
  [[ -d "$BARE_ROOT/worktrees/test-target/.test-target/issues" ]]

  # Verify tag exists
  cd "$BARE_ROOT/worktrees/test-target"
  run git tag -l "test-target/initial"
  assert_output "test-target/initial"
}

# ---------------------------------------------------------------------------
# init: duplicate detection
# ---------------------------------------------------------------------------
@test "init: detects existing test-target worktree" {
  _init_test_target

  # Verify worktree is listed (simulating the check in test-project-init.md)
  run git -C "$BARE_ROOT" worktree list
  assert_output --partial "test-target"

  # A second init would detect this via the same check
  local found=false
  if git -C "$BARE_ROOT" worktree list | grep -q "test-target"; then
    found=true
  fi
  [[ "$found" == "true" ]]
}

# ---------------------------------------------------------------------------
# reset: normal case
# ---------------------------------------------------------------------------
@test "reset: restores to initial tag state" {
  _init_test_target

  local wt_path="$BARE_ROOT/worktrees/test-target"

  # Make changes after init
  echo "modified" > "$wt_path/extra-file.txt"
  cd "$wt_path"
  git add -A && git commit -m "extra change" 2>/dev/null

  # Record initial commit hash
  local initial_hash
  initial_hash=$(git rev-parse test-target/initial)

  # Reset to initial state
  git reset --hard test-target/initial
  git clean -fdx

  # Verify hash matches initial
  local current_hash
  current_hash=$(git rev-parse HEAD)
  [[ "$current_hash" == "$initial_hash" ]]

  # Verify extra file is gone
  [[ ! -f "$wt_path/extra-file.txt" ]]
}

# ---------------------------------------------------------------------------
# reset: cwd safety check
# ---------------------------------------------------------------------------
@test "reset: rejects when cwd is inside test-target worktree" {
  _init_test_target

  local wt_path="$BARE_ROOT/worktrees/test-target"
  cd "$wt_path"

  # Simulate the cwd check from test-project-reset.md
  local current_dir
  current_dir="$(pwd)"
  local rejected=false
  if [[ "$current_dir" == "$wt_path"* ]]; then
    rejected=true
  fi
  [[ "$rejected" == "true" ]]
}

# ---------------------------------------------------------------------------
# scenario-load: normal case (smoke-001)
# ---------------------------------------------------------------------------
@test "scenario-load: places issue files for smoke-001" {
  _init_test_target

  local wt_path="$BARE_ROOT/worktrees/test-target"
  local issues_dir="$wt_path/.test-target/issues"

  # Simulate scenario-load for smoke-001
  mkdir -p "$issues_dir"
  rm -f "$issues_dir"/*.md

  cat > "$issues_dir/TEST-001.md" <<'EOF'
---
id: TEST-001
title: "[Test] add hello world function"
labels: [test, scope/test-target]
status: open
---

## 概要
scripts/helper.sh に hello_world 関数を追加する。
## 受け入れ基準
- [ ] hello_world 関数が存在する
- [ ] 呼び出すと "Hello, World!" を stdout に出力する
EOF

  cd "$wt_path"
  git add -A && git commit -m "chore(test): load scenario smoke-001" 2>/dev/null

  # Verify issue file exists
  [[ -f "$issues_dir/TEST-001.md" ]]

  # Verify content
  run cat "$issues_dir/TEST-001.md"
  assert_output --partial "hello_world"

  # Verify commit message
  run git log --oneline -1
  assert_output --partial "smoke-001"
}

# ---------------------------------------------------------------------------
# scenario-load: invalid scenario name
# ---------------------------------------------------------------------------
@test "scenario-load: rejects nonexistent scenario" {
  _init_test_target

  # Simulate scenario validation logic
  local scenario_name="nonexistent-999"
  local known_scenarios=("smoke-001" "smoke-002")
  local found=false

  for s in "${known_scenarios[@]}"; do
    if [[ "$s" == "$scenario_name" ]]; then
      found=true
      break
    fi
  done

  [[ "$found" == "false" ]]
}
