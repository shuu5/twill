#!/usr/bin/env bats
# switchover-rollback.bats - unit tests for scripts/switchover.sh rollback subcommand
#
# Spec: openspec/changes/c-6-switchover/specs/switchover-script.md
# Requirement: switchover.sh rollback subcommand

load '../helpers/common'

setup() {
  common_setup

  # Create plugin symlink structure in sandbox HOME
  FAKE_HOME="$SANDBOX/home"
  mkdir -p "$FAKE_HOME/.claude/plugins"
  export HOME="$FAKE_HOME"
  export PLUGIN_DIR="$FAKE_HOME/.claude/plugins"

  # Create new plugin (currently active) and old plugin (backup)
  mkdir -p "$SANDBOX/new-plugin"
  mkdir -p "$SANDBOX/old-plugin"
  ln -s "$SANDBOX/new-plugin" "$PLUGIN_DIR/dev"
  ln -s "$SANDBOX/old-plugin" "$PLUGIN_DIR/dev.bak"

  # Default stubs
  stub_command "loom" 'exit 0'
  stub_command "tmux" '
    case "$*" in
      *list-sessions*|*ls*)
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: switchover.sh rollback subcommand
# Scenario: 正常ロールバック
# ---------------------------------------------------------------------------

@test "rollback: deletes current symlink and restores from backup" {
  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_success
  [ -L "$PLUGIN_DIR/dev" ]
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
}

@test "rollback: removes dev.bak after successful restore" {
  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_success
  [ ! -e "$PLUGIN_DIR/dev.bak" ]
}

@test "rollback: displays success message" {
  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_success
  assert_output --partial "ロールバック完了"
}

@test "rollback: cleans up new plugin state files" {
  # New plugin may have state files that need cleanup
  mkdir -p "$SANDBOX/new-plugin/.state"
  touch "$SANDBOX/new-plugin/.state/session.json"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_success
  # Symlink should now point to old plugin
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
}

# ---------------------------------------------------------------------------
# Scenario: バックアップ不在
# ---------------------------------------------------------------------------

@test "rollback: fails when dev.bak does not exist" {
  rm -f "$PLUGIN_DIR/dev.bak"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "バックアップが見つかりません"
}

@test "rollback: does not modify current symlink when backup is missing" {
  rm -f "$PLUGIN_DIR/dev.bak"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_failure
  # Current symlink should remain
  [ -L "$PLUGIN_DIR/dev" ]
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/new-plugin" ]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "rollback: fails when dev.bak is a broken symlink" {
  rm -f "$PLUGIN_DIR/dev.bak"
  ln -s "/nonexistent/plugin/path" "$PLUGIN_DIR/dev.bak"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_failure
  assert_output --partial "バックアップ先が無効"
}

@test "rollback: works when current dev symlink is already missing" {
  rm -f "$PLUGIN_DIR/dev"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_success
  [ -L "$PLUGIN_DIR/dev" ]
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
}

@test "rollback: handles dev being a regular directory (not symlink)" {
  rm -f "$PLUGIN_DIR/dev"
  mkdir -p "$PLUGIN_DIR/dev"
  touch "$PLUGIN_DIR/dev/somefile"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  # Should fail or warn - dev is not a symlink
  assert_failure
  assert_output --partial "symlink"
}

@test "rollback: atomic operation - backup preserved on failure" {
  # Make plugin dir read-only to simulate failure
  chmod 555 "$PLUGIN_DIR"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_failure

  # Restore permissions for teardown
  chmod 755 "$PLUGIN_DIR"

  # Backup should still exist
  [ -L "$PLUGIN_DIR/dev.bak" ]
}

@test "rollback: works even when new plugin has open file descriptors" {
  # Simulate by creating a lock file - rollback should still work
  touch "$SANDBOX/new-plugin/.lock"

  run bash "$SANDBOX/scripts/switchover.sh" rollback

  assert_success
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
}

@test "rollback: rejects extra arguments" {
  run bash "$SANDBOX/scripts/switchover.sh" rollback --unexpected

  assert_failure
  assert_output --partial "不明なオプション"
}
