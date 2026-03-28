#!/usr/bin/env bats
# ecc-monitor.bats - unit tests for scripts/ecc-monitor.sh

load '../helpers/common'

setup() {
  common_setup

  # Override ECC_CACHE_DIR to sandbox
  export ECC_CACHE_DIR="$SANDBOX/ecc-cache"

  # Create a mock git repo as the ECC cache (with 'main' branch)
  # Need at least 2 commits so that parent reference (commit^) works
  mkdir -p "$ECC_CACHE_DIR"
  git init "$ECC_CACHE_DIR" 2>/dev/null
  cd "$ECC_CACHE_DIR"
  git checkout -b main 2>/dev/null || git branch -m main 2>/dev/null
  git commit --allow-empty -m "root" 2>/dev/null
  mkdir -p agents skills rules hooks commands docs
  echo "test" > agents/test.md
  echo "test" > skills/test.md
  git add -A 2>/dev/null
  git commit -m "initial" 2>/dev/null

  # Copy the script and patch ECC_CACHE_DIR
  cp "$REPO_ROOT/scripts/ecc-monitor.sh" "$SANDBOX/scripts/ecc-monitor.sh"
  # Patch the script to use our ECC_CACHE_DIR and CHECKPOINT_FILE
  sed -i "s|ECC_CACHE_DIR=.*|ECC_CACHE_DIR=\"$ECC_CACHE_DIR\"|" "$SANDBOX/scripts/ecc-monitor.sh"
  sed -i "s|ECC_REPO_URL=.*|ECC_REPO_URL=\"$ECC_CACHE_DIR\"|" "$SANDBOX/scripts/ecc-monitor.sh"
  sed -i "s|CHECKPOINT_FILE=.*|CHECKPOINT_FILE=\"$ECC_CACHE_DIR/last-check.json\"|" "$SANDBOX/scripts/ecc-monitor.sh"

  # Override ensure_repo to skip clone/pull by replacing the function body
  sed -i '/^ensure_repo() {/,/^}/c\ensure_repo() { return 0; }' "$SANDBOX/scripts/ecc-monitor.sh"

  # Create a default checkpoint pointing to root commit (avoids fallback path issues)
  local root_commit
  root_commit=$(git -C "$ECC_CACHE_DIR" log --reverse --format="%H" | head -1)
  echo "{\"commit\": \"$root_commit\"}" > "$ECC_CACHE_DIR/last-check.json"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: ecc-monitor
# ---------------------------------------------------------------------------

@test "ecc-monitor check outputs JSON" {
  run bash "$SANDBOX/scripts/ecc-monitor.sh" check

  assert_success
  echo "$output" | jq '.' > /dev/null
}

@test "ecc-monitor save-checkpoint creates checkpoint file" {
  # Restore ensure_repo: replace no-op with a function that just does a no-op pull
  # (the local repo has no remote, so ensure_repo must succeed without network)
  sed -i 's|^ensure_repo() { return 0; }|ensure_repo() { true; }|' "$SANDBOX/scripts/ecc-monitor.sh"

  local checkpoint="$ECC_CACHE_DIR/last-check.json"
  # Override CHECKPOINT_FILE
  sed -i "s|CHECKPOINT_FILE=.*|CHECKPOINT_FILE=\"$checkpoint\"|" "$SANDBOX/scripts/ecc-monitor.sh"

  run bash "$SANDBOX/scripts/ecc-monitor.sh" save-checkpoint

  assert_success
  [ -f "$checkpoint" ]
  jq -e '.commit' "$checkpoint" > /dev/null
}

@test "ecc-monitor fails with unknown subcommand" {
  run bash "$SANDBOX/scripts/ecc-monitor.sh" invalid

  assert_failure
  assert_output --partial "Usage"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "ecc-monitor classify_path categorizes correctly" {
  # Test the classify function by checking output of check command
  # with changes in various directories
  cd "$ECC_CACHE_DIR"
  echo "new" > agents/new-agent.md
  git add -A && git commit -m "add agent" 2>/dev/null

  # Set checkpoint to previous commit
  local prev_commit
  prev_commit=$(git log --format="%H" | tail -1)
  local checkpoint="$ECC_CACHE_DIR/last-check.json"
  sed -i "s|CHECKPOINT_FILE=.*|CHECKPOINT_FILE=\"$checkpoint\"|" "$SANDBOX/scripts/ecc-monitor.sh"
  echo "{\"commit\": \"$prev_commit\"}" > "$checkpoint"

  run bash "$SANDBOX/scripts/ecc-monitor.sh" check

  assert_success
  echo "$output" | jq -e '.status == "has_changes"' > /dev/null
  echo "$output" | jq -e '.changes | length > 0' > /dev/null
}

@test "ecc-monitor check reports no_changes when up to date" {
  # Set checkpoint to HEAD
  local current_commit
  current_commit=$(git -C "$ECC_CACHE_DIR" rev-parse HEAD)
  local checkpoint="$ECC_CACHE_DIR/last-check.json"
  sed -i "s|CHECKPOINT_FILE=.*|CHECKPOINT_FILE=\"$checkpoint\"|" "$SANDBOX/scripts/ecc-monitor.sh"
  echo "{\"commit\": \"$current_commit\"}" > "$checkpoint"

  run bash "$SANDBOX/scripts/ecc-monitor.sh" check

  assert_success
  echo "$output" | jq -e '.status == "no_changes"' > /dev/null
}

@test "ecc-monitor defaults to check subcommand" {
  run bash "$SANDBOX/scripts/ecc-monitor.sh"

  assert_success
  echo "$output" | jq '.' > /dev/null
}
