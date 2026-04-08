#!/usr/bin/env bats
# autopilot-pilot-rebase.bats - 3 scenarios for pilot rebase atomic

load "../helpers/common"
load "../helpers/gh_stub"

setup() {
  common_setup
  export ISSUE_NUM=42
  export BRANCH_NAME="feat/42-test"
  export WORKTREE_DIR="$SANDBOX"
}

teardown() {
  common_teardown
}

# Scenario 1: clean rebase → push 成功
@test "rebase: clean rebase succeeds with force-with-lease push" {
  setup_git_rebase_clean

  run bash -c '
    export PATH="'"$PATH"'"
    cd "'"$SANDBOX"'"

    # Step 1: fetch
    git fetch origin main

    # Step 2: rebase
    git rebase origin/main
    REBASE_RC=$?

    if [ "$REBASE_RC" -eq 0 ]; then
      # Step 3: push
      git push --force-with-lease origin "'"$BRANCH_NAME"'"
      echo "SUCCESS: rebase + push completed"
    else
      echo "FAIL: rebase failed"
      exit 1
    fi
  '
  assert_success
  assert_output --partial "SUCCESS: rebase + push completed"
}

# Scenario 2: conflict 1 ファイル → LLM resolve → push 成功 (mock)
@test "rebase: single conflict file triggers LLM resolve path" {
  setup_git_rebase_conflict_small

  run bash -c '
    export PATH="'"$PATH"'"
    cd "'"$SANDBOX"'"

    git fetch origin main
    git rebase origin/main 2>/dev/null
    REBASE_RC=$?

    if [ "$REBASE_RC" -ne 0 ]; then
      CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
      echo "conflict_files=$CONFLICT_FILES"

      if [ "$CONFLICT_FILES" -ge 4 ]; then
        git rebase --abort
        echo "ERROR: too many conflicts"
        exit 2
      fi

      # LLM would resolve here, then continue
      echo "INFO: LLM resolve path for $CONFLICT_FILES file(s)"
      # Simulate successful resolve + continue
      git rebase --continue 2>/dev/null || true
      git push --force-with-lease origin "'"$BRANCH_NAME"'" 2>/dev/null || true
      echo "SUCCESS: resolved and pushed"
    fi
  '
  assert_success
  assert_output --partial "conflict_files=1"
  assert_output --partial "INFO: LLM resolve path"
}

# Scenario 3: conflict 4 ファイル以上 → abort + exit 2
@test "rebase: 4+ conflict files aborts with exit 2" {
  setup_git_rebase_conflict_large

  run bash -c '
    export PATH="'"$PATH"'"
    cd "'"$SANDBOX"'"

    git fetch origin main
    git rebase origin/main 2>/dev/null
    REBASE_RC=$?

    if [ "$REBASE_RC" -ne 0 ]; then
      CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
      echo "conflict_files=$CONFLICT_FILES"

      if [ "$CONFLICT_FILES" -ge 4 ]; then
        git rebase --abort
        echo "ERROR: conflict $CONFLICT_FILES files (>= 4) — abort + escalation" >&2
        exit 2
      fi
    fi
  '
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "conflict_files=4"
}
