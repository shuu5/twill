#!/usr/bin/env bats
# worktree-delete-gitdir-validation.bats
# Unit / edge-case tests for the gitdir path-traversal validation added to
# scripts/worktree-delete.sh.
#
# Spec: openspec/changes/tech-debt-worktree-delete-gitdir-validation/specs/gitdir-validation.md
# Design: openspec/changes/tech-debt-worktree-delete-gitdir-validation/design.md

load '../helpers/common'

setup() {
  common_setup

  # Stub git so we never touch a real repo.
  stub_command "git" '
    case "$*" in
      *"worktree remove"*) exit 0 ;;
      *"worktree list"*)   echo "" ;;
      *"branch --list"*)   echo "" ;;
      *"branch"*)          exit 0 ;;
      *)                   exit 0 ;;
    esac
  '

  # Use the sandbox copy so that SCRIPT_DIR/../ resolves to SANDBOX,
  # allowing _write_git_pointer to control PROJECT_ROOT via .git placement.
  SCRIPT="$SANDBOX/scripts/worktree-delete.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: write a .git pointer file in SANDBOX and set PROJECT_ROOT so that
# worktree-delete.sh discovers it.
# ---------------------------------------------------------------------------
_write_git_pointer() {
  local gitdir_value="$1"
  echo "gitdir: ${gitdir_value}" > "$SANDBOX/.git"
  export PROJECT_ROOT="$SANDBOX"
}

# ---------------------------------------------------------------------------
# Requirement: worktree-delete.sh gitdir パストラバーサル検証
# ---------------------------------------------------------------------------

# Scenario: gitdir に `..` が含まれる場合
# WHEN .git ファイルの gitdir: 値が `..` を含む（例: gitdir: /path/../.bare）
# THEN ERROR メッセージを stderr に出力し exit 1 で終了する
@test "gitdir containing .. is rejected with error to stderr and exit 1" {
  _write_git_pointer "/path/../.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  assert_failure
  assert_output --partial "ERROR"
  assert_output --partial ".."
}

# Scenario: 正常な gitdir 値の場合
# WHEN .git の gitdir: 値が `..` を含まない正常なパス（例: /home/user/project/.bare）
# THEN 検証を通過し、bare_root 構築ロジックへ進む（validationエラーにならない）
@test "gitdir without .. passes validation and proceeds to bare_root logic" {
  _write_git_pointer "/home/user/project/.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  # Must NOT emit a path-traversal / gitdir validation error.
  [[ "$output" != *"不正なパスコンポーネント"* ]]
  # The script continues past gitdir validation and reaches the worktree-existence
  # check (WARN or ERROR about worktree path), which means bare_root was built.
  [[ "$output" == *"worktree"* ]] || [[ "$output" == *"bare"* ]] || [[ "$output" == *"WARN"* ]] || [[ "$output" == *"ERROR"* ]]
}

# Scenario: gitdir が `.bare` で終わる場合（既存パターン）
# WHEN 検証通過後に gitdir が /\.bare$ にマッチ
# THEN bare_root="${gitdir%/.bare}/" を設定して通常処理を継続する
@test "gitdir ending with /.bare uses bare_root extraction and continues" {
  # Point bare_root to a real directory so the script gets past bare detection.
  mkdir -p "$SANDBOX/project"
  mkdir -p "$SANDBOX/project/worktrees"
  _write_git_pointer "$SANDBOX/project/.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/nonexistent-branch"

  # Must not fail on gitdir validation.
  [[ "$output" != *"不正なパスコンポーネント"* ]]
  # Should reach the worktree-existence check (WARN or OK output).
  assert_output --partial "worktree"
}

# Scenario: gitdir が `.bare/worktrees/...` パターンの場合（既存パターン）
# WHEN 検証通過後に gitdir が `.bare/` を含む（例: /home/user/project/.bare/worktrees/main）
# THEN bare_root=$(echo "$gitdir" | sed 's|/\.bare/.*|/|') を設定して継続する
@test "gitdir with .bare/worktrees pattern extracts bare_root and continues" {
  mkdir -p "$SANDBOX/project"
  mkdir -p "$SANDBOX/project/worktrees"
  _write_git_pointer "$SANDBOX/project/.bare/worktrees/main"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/nonexistent-branch"

  [[ "$output" != *"不正なパスコンポーネント"* ]]
  assert_output --partial "worktree"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Edge: gitdir is empty string
# An empty gitdir should not crash with a path-traversal error but may fail
# at bare_root construction.
@test "empty gitdir does not trigger path-traversal error" {
  _write_git_pointer ""

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  # Must not emit a path-traversal / gitdir validation error.
  [[ "$output" != *"不正なパスコンポーネント"* ]]
}

# Edge: gitdir contains `..` in the middle of the path
@test "gitdir with .. in the middle is rejected" {
  _write_git_pointer "/home/user/project/../../etc/.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  assert_failure
  assert_output --partial "ERROR"
  assert_output --partial ".."
}

# Edge: gitdir starts with .. (relative path, rejected by absolute-path check)
@test "gitdir starting with .. is rejected" {
  _write_git_pointer "../.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  assert_failure
  assert_output --partial "ERROR"
  # Rejected by absolute-path check first; no ".." in the error message.
}

# Edge: gitdir contains .. followed immediately by component (e.g. ..hidden)
# "..hidden" is NOT a real traversal component — the regex boundary check
# must allow it through (only /../ or /.. at end-of-path is blocked).
@test "gitdir with ..hidden component is NOT rejected (boundary check)" {
  _write_git_pointer "/home/user/..hidden/.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  # Boundary-aware check: "..hidden" passes because it is not a ".." component.
  [[ "$output" != *"不正なパスコンポーネント"* ]]
}

# Edge: gitdir contains a single dot component (.)
# A single "." is not a traversal component; validation must pass it.
@test "gitdir with single dot component is not rejected" {
  _write_git_pointer "/home/user/./project/.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  [[ "$output" != *"不正なパスコンポーネント"* ]]
}

# Edge: error message is written to stderr, not stdout
@test "gitdir path-traversal error is written to stderr" {
  _write_git_pointer "/path/../.bare"

  cd "$SANDBOX"
  # Capture stdout and stderr separately.
  run bash -c "bash '$SCRIPT' 'feat/x' 2>/dev/null"

  # stdout should be empty (error is on stderr, not stdout)
  [ -z "$output" ]
}

@test "gitdir path-traversal error message appears on stderr stream" {
  _write_git_pointer "/path/../.bare"

  cd "$SANDBOX"
  run bash -c "bash '$SCRIPT' 'feat/x' 2>&1 1>/dev/null"

  assert_failure
  assert_output --partial "ERROR"
}

# Edge: gitdir is a relative path (not starting with /)
# Relative paths could be used for traversal; must be rejected.
@test "relative gitdir path is rejected" {
  _write_git_pointer "relative/path/.bare"

  cd "$SANDBOX"
  run bash "$SCRIPT" "feat/some-branch"

  assert_failure
  assert_output --partial "ERROR"
}
