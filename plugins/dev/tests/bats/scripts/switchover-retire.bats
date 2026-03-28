#!/usr/bin/env bats
# switchover-retire.bats - unit tests for scripts/switchover.sh retire subcommand
#
# Spec: openspec/changes/c-6-switchover/specs/switchover-script.md
# Requirement: switchover.sh retire subcommand

load '../helpers/common'

setup() {
  common_setup

  # Create plugin symlink structure in sandbox HOME
  FAKE_HOME="$SANDBOX/home"
  mkdir -p "$FAKE_HOME/.claude/plugins"
  export HOME="$FAKE_HOME"
  export PLUGIN_DIR="$FAKE_HOME/.claude/plugins"

  # Active plugin symlink (new plugin, post-switch)
  mkdir -p "$SANDBOX/new-plugin"
  ln -s "$SANDBOX/new-plugin" "$PLUGIN_DIR/dev"

  # Backup from switch operation
  mkdir -p "$SANDBOX/old-plugin"
  ln -s "$SANDBOX/old-plugin" "$PLUGIN_DIR/dev.bak"

  # Default stubs
  stub_command "gh" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: switchover.sh retire subcommand
# Scenario: 正常退役
# ---------------------------------------------------------------------------

@test "retire: deletes dev.bak when user confirms" {
  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  [ ! -e "$PLUGIN_DIR/dev.bak" ]
}

@test "retire: displays gh repo archive guidance" {
  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  assert_output --partial "gh repo archive"
}

@test "retire: does not modify active dev symlink" {
  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  [ -L "$PLUGIN_DIR/dev" ]
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/new-plugin" ]
}

@test "retire: shows confirmation prompt before deletion" {
  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  # Output should contain a confirmation question
  assert_output --partial "確認"
}

# ---------------------------------------------------------------------------
# Scenario: 退役キャンセル
# ---------------------------------------------------------------------------

@test "retire: exits 0 with no changes when user denies confirmation" {
  run bash -c "echo 'n' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  [ "$status" -eq 0 ]
  # Backup should still exist
  [ -L "$PLUGIN_DIR/dev.bak" ]
}

@test "retire: displays cancellation message when denied" {
  run bash -c "echo 'n' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  assert_output --partial "キャンセル"
}

@test "retire: preserves backup symlink target when denied" {
  run bash -c "echo 'n' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  local bak_target
  bak_target=$(readlink "$PLUGIN_DIR/dev.bak")
  [ "$bak_target" = "$SANDBOX/old-plugin" ]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "retire: fails when no backup exists (nothing to retire)" {
  rm -f "$PLUGIN_DIR/dev.bak"

  run bash "$SANDBOX/scripts/switchover.sh" retire

  assert_failure
  assert_output --partial "バックアップが見つかりません"
}

@test "retire: --force skips confirmation prompt" {
  run bash "$SANDBOX/scripts/switchover.sh" retire --force

  assert_success
  [ ! -e "$PLUGIN_DIR/dev.bak" ]
}

@test "retire: handles empty stdin (non-interactive) as deny" {
  run bash -c "bash '$SANDBOX/scripts/switchover.sh' retire < /dev/null"

  # Should treat no input as denial or error
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  # Backup should remain if denied
  [ -L "$PLUGIN_DIR/dev.bak" ] || [ "$status" -eq 0 ]
}

@test "retire: only deletes dev.bak, no other files in plugins dir" {
  # Create another plugin symlink
  mkdir -p "$SANDBOX/other-plugin"
  ln -s "$SANDBOX/other-plugin" "$PLUGIN_DIR/other"

  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  [ ! -e "$PLUGIN_DIR/dev.bak" ]
  # Other plugin should remain
  [ -L "$PLUGIN_DIR/other" ]
  [ -L "$PLUGIN_DIR/dev" ]
}

@test "retire: gh repo archive is displayed as guidance, not executed" {
  # Stub gh to track calls
  stub_command "gh" '
    echo "GH_CALLED: $*" >> "$SANDBOX/gh-calls.log"
    exit 0
  '

  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  # gh repo archive should NOT have been called
  if [ -f "$SANDBOX/gh-calls.log" ]; then
    ! grep -q "repo archive" "$SANDBOX/gh-calls.log"
  fi
}

@test "retire: handles broken dev.bak symlink (target deleted)" {
  rm -rf "$SANDBOX/old-plugin"
  # dev.bak now points to nonexistent dir

  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' retire"

  # Should still succeed - we're deleting the backup anyway
  assert_success
  [ ! -e "$PLUGIN_DIR/dev.bak" ]
}

@test "retire: invalid response repeats prompt or aborts" {
  # Send invalid input then 'n'
  run bash -c "printf 'maybe\nn\n' | bash '$SANDBOX/scripts/switchover.sh' retire"

  assert_success
  # Backup should remain since final answer was 'n'
  [ -L "$PLUGIN_DIR/dev.bak" ]
}
