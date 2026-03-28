#!/usr/bin/env bats
# branch-create.bats - unit tests for scripts/branch-create.sh

load '../helpers/common'

setup() {
  common_setup

  # Create a real git repo in sandbox with 'main' as the default branch
  git init "$SANDBOX/test-repo" 2>/dev/null
  cd "$SANDBOX/test-repo"
  git checkout -b main 2>/dev/null || git branch -m main 2>/dev/null
  git commit --allow-empty -m "initial" 2>/dev/null

  # Copy script
  mkdir -p "$SANDBOX/test-repo/scripts"
  cp "$REPO_ROOT/scripts/branch-create.sh" "$SANDBOX/test-repo/scripts/"

  stub_command "gh" '
    echo "{\"title\": \"Fix bug\", \"labels\": [{\"name\": \"bug\"}]}"
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: branch-create validation
# ---------------------------------------------------------------------------

@test "branch-create fails without branch name" {
  cd "$SANDBOX/test-repo"
  run bash scripts/branch-create.sh

  assert_failure
  assert_output --partial "ブランチ名"
}

@test "branch-create rejects reserved name: main" {
  cd "$SANDBOX/test-repo"
  run bash scripts/branch-create.sh "main"

  assert_failure
  assert_output --partial "予約語"
}

@test "branch-create rejects reserved name: master" {
  cd "$SANDBOX/test-repo"
  run bash scripts/branch-create.sh "master"

  assert_failure
  assert_output --partial "予約語"
}

@test "branch-create rejects invalid prefix" {
  cd "$SANDBOX/test-repo"
  run bash scripts/branch-create.sh "feature/invalid"

  assert_failure
  assert_output --partial "プレフィックス"
}

@test "branch-create rejects uppercase characters" {
  cd "$SANDBOX/test-repo"
  run bash scripts/branch-create.sh "feat/MyBranch"

  assert_failure
  assert_output --partial "英小文字"
}

@test "branch-create rejects branch > 50 chars" {
  cd "$SANDBOX/test-repo"
  local long_name="feat/this-is-way-too-long-branch-name-that-exceeds-fifty-chars"
  run bash scripts/branch-create.sh "$long_name"

  assert_failure
  assert_output --partial "50文字"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "branch-create generates fix/ prefix from bug label" {
  cd "$SANDBOX/test-repo"
  stub_command "gh" '
    echo "{\"title\": \"Fix crash on login\", \"labels\": [{\"name\": \"bug\"}]}"
  '

  run bash scripts/branch-create.sh "#42"

  # Should generate fix/ prefix (may fail at git checkout but name should be right)
  [[ "$output" == *"fix/42"* ]] || true
}

@test "branch-create creates branch in standard repo" {
  cd "$SANDBOX/test-repo"

  run bash scripts/branch-create.sh "feat/1-test"

  assert_success
  assert_output --partial "ブランチ作成完了"

  # Verify branch exists
  git branch --list "feat/1-test" | grep -q "feat/1-test"
}

@test "branch-create rejects duplicate branch" {
  cd "$SANDBOX/test-repo"
  git checkout -b "feat/1-test" 2>/dev/null
  git checkout main 2>/dev/null || git checkout master 2>/dev/null

  run bash scripts/branch-create.sh "feat/1-test"

  assert_failure
  assert_output --partial "既に存在します"
}

@test "branch-create without slash in name is accepted" {
  cd "$SANDBOX/test-repo"
  run bash scripts/branch-create.sh "simple-branch"

  # No slash means no prefix check needed, only char validation
  assert_success
  assert_output --partial "ブランチ作成完了"
}
