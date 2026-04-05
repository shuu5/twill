#!/usr/bin/env bats
# project-migrate.bats - unit tests for scripts/project-migrate.sh

load '../helpers/common'

setup() {
  common_setup
  stub_command "deltaspec" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: project-migrate
# ---------------------------------------------------------------------------

@test "project-migrate fails outside git repo" {
  cd "$SANDBOX"
  # No .git or CLAUDE.md

  run bash "$SANDBOX/scripts/project-migrate.sh" --dry-run

  assert_failure
  assert_output --partial "プロジェクトルート"
}

@test "project-migrate --dry-run shows changes without applying" {
  cd "$SANDBOX"
  git init . 2>/dev/null
  # Create package.json to trigger webapp-llm detection
  echo '{}' > package.json

  run bash "$SANDBOX/scripts/project-migrate.sh" --dry-run

  assert_success
  assert_output --partial "dry-run 完了"
}

@test "project-migrate --help shows usage" {
  run bash "$SANDBOX/scripts/project-migrate.sh" --help

  assert_success
  assert_output --partial "使用方法"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "project-migrate auto-detects rnaseq type" {
  cd "$SANDBOX"
  git init . 2>/dev/null
  touch renv.lock

  run bash "$SANDBOX/scripts/project-migrate.sh" --dry-run

  assert_success
  assert_output --partial "rnaseq"
}

@test "project-migrate auto-detects webapp-llm type" {
  cd "$SANDBOX"
  git init . 2>/dev/null
  echo '{"name": "test"}' > package.json

  run bash "$SANDBOX/scripts/project-migrate.sh" --dry-run

  assert_success
  assert_output --partial "webapp-llm"
}

@test "project-migrate fails with unknown type when no markers present" {
  cd "$SANDBOX"
  git init . 2>/dev/null
  # Just have CLAUDE.md, no type markers
  echo "# Test" > CLAUDE.md

  run bash "$SANDBOX/scripts/project-migrate.sh" --dry-run

  # Should fail because it can't detect type
  assert_failure
  assert_output --partial "プロジェクトタイプを自動検出できません"
}

@test "project-migrate rejects worktree root execution" {
  cd "$SANDBOX"
  # Simulate worktree root with .git dir and worktrees subdir
  mkdir -p .git/worktrees
  mkdir -p main
  # Create main/.git as file (worktree pointer)
  echo "gitdir: ../.git/worktrees/main" > main/.git

  run bash "$SANDBOX/scripts/project-migrate.sh" --dry-run

  assert_failure
  assert_output --partial "main/"
}
