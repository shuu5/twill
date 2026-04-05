#!/usr/bin/env bats
# project-create.bats - unit tests for scripts/project-create.sh

load '../helpers/common'

setup() {
  common_setup

  # Set up template directories
  export PROJECTS_ROOT="$SANDBOX/projects"
  mkdir -p "$SANDBOX/projects"

  # Stub external commands
  stub_command "gh" 'exit 0'
  stub_command "deltaspec" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: project-create
# ---------------------------------------------------------------------------

@test "project-create fails without project name" {
  run bash "$SANDBOX/scripts/project-create.sh"

  assert_failure
  assert_output --partial "プロジェクト名"
}

@test "project-create rejects invalid project name (uppercase)" {
  run bash "$SANDBOX/scripts/project-create.sh" "MyProject"

  assert_failure
  assert_output --partial "英小文字"
}

@test "project-create rejects invalid project name (special chars)" {
  run bash "$SANDBOX/scripts/project-create.sh" "my_project!"

  assert_failure
  assert_output --partial "英小文字"
}

@test "project-create rejects unknown project type" {
  run bash "$SANDBOX/scripts/project-create.sh" "test-proj" --type "nonexistent"

  assert_failure
  assert_output --partial "不明なプロジェクトタイプ"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "project-create shows help with --help" {
  run bash "$SANDBOX/scripts/project-create.sh" --help

  assert_success
  assert_output --partial "使用方法"
}

@test "project-create rejects duplicate project" {
  mkdir -p "$SANDBOX/projects/existing-proj"

  PROJECTS_ROOT="$SANDBOX/projects" \
  run bash "$SANDBOX/scripts/project-create.sh" "existing-proj" --root "$SANDBOX/projects" --no-github

  assert_failure
  assert_output --partial "既に存在します"
}

@test "project-create accepts single-char project name" {
  # "a" should be valid
  PROJECTS_ROOT="$SANDBOX/projects" \
  run bash "$SANDBOX/scripts/project-create.sh" "a" --root "$SANDBOX/projects" --no-github

  # Should get past validation (may fail on template copy but that's OK)
  [[ "$output" != *"英小文字"* ]]
}

@test "project-create --no-github skips GitHub repo creation" {
  # Patch sandbox copy: use --allow-empty so commit succeeds even without template files
  sed -i 's/git commit -m/git commit --allow-empty -m/' "$SANDBOX/scripts/project-create.sh"

  run bash "$SANDBOX/scripts/project-create.sh" "test-proj" --root "$SANDBOX/projects" --no-github

  assert_success
  assert_output --partial "GitHubリポジトリ作成をスキップ"
}
