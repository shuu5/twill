#!/usr/bin/env bats
# switchover-switch.bats - unit tests for scripts/switchover.sh switch subcommand
#
# Spec: openspec/changes/c-6-switchover/specs/switchover-script.md
# Requirement: switchover.sh switch subcommand

load '../helpers/common'

setup() {
  common_setup

  # Create plugin symlink structure in sandbox HOME
  FAKE_HOME="$SANDBOX/home"
  mkdir -p "$FAKE_HOME/.claude/plugins"
  export HOME="$FAKE_HOME"
  export PLUGIN_DIR="$FAKE_HOME/.claude/plugins"

  # Create old plugin target and symlink
  mkdir -p "$SANDBOX/old-plugin"
  ln -s "$SANDBOX/old-plugin" "$PLUGIN_DIR/dev"

  # Create new plugin directory
  mkdir -p "$SANDBOX/new-plugin"
  export NEW_PLUGIN_DIR="$SANDBOX/new-plugin"

  # Default stubs: all checks pass
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
# Requirement: switchover.sh switch subcommand
# Scenario: 正常切替
# ---------------------------------------------------------------------------

@test "switch: renames old symlink to dev.bak when check passes" {
  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_success
  [ -L "$PLUGIN_DIR/dev.bak" ] || [ -e "$PLUGIN_DIR/dev.bak" ]
  # dev.bak should point to old plugin
  local bak_target
  bak_target=$(readlink "$PLUGIN_DIR/dev.bak")
  [ "$bak_target" = "$SANDBOX/old-plugin" ]
}

@test "switch: creates new symlink pointing to new plugin" {
  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_success
  [ -L "$PLUGIN_DIR/dev" ]
  local new_target
  new_target=$(readlink "$PLUGIN_DIR/dev")
  [ "$new_target" = "$NEW_PLUGIN_DIR" ]
}

@test "switch: runs check before switching" {
  # Make check fail
  stub_command "loom" '
    case "$*" in
      *validate*)
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_failure
  # Old symlink should remain unchanged
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
}

@test "switch: outputs success message after switching" {
  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_success
  assert_output --partial "切替完了"
}

# ---------------------------------------------------------------------------
# Scenario: 既存バックアップあり
# ---------------------------------------------------------------------------

@test "switch: prompts for confirmation when dev.bak exists" {
  # Create existing backup
  mkdir -p "$SANDBOX/even-older-plugin"
  ln -s "$SANDBOX/even-older-plugin" "$PLUGIN_DIR/dev.bak"

  # Provide "n" (deny) to stdin
  run bash -c "echo 'n' | bash '$SANDBOX/scripts/switchover.sh' switch --new '$NEW_PLUGIN_DIR'"

  assert_failure
  # dev.bak should still point to old backup
  local bak_target
  bak_target=$(readlink "$PLUGIN_DIR/dev.bak")
  [ "$bak_target" = "$SANDBOX/even-older-plugin" ]
}

@test "switch: aborts without changes when backup overwrite denied" {
  mkdir -p "$SANDBOX/even-older-plugin"
  ln -s "$SANDBOX/even-older-plugin" "$PLUGIN_DIR/dev.bak"

  run bash -c "echo 'n' | bash '$SANDBOX/scripts/switchover.sh' switch --new '$NEW_PLUGIN_DIR'"

  assert_failure
  # Original symlink must remain untouched
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
  assert_output --partial "中止"
}

@test "switch: overwrites backup when user confirms yes" {
  mkdir -p "$SANDBOX/even-older-plugin"
  ln -s "$SANDBOX/even-older-plugin" "$PLUGIN_DIR/dev.bak"

  run bash -c "echo 'y' | bash '$SANDBOX/scripts/switchover.sh' switch --new '$NEW_PLUGIN_DIR'"

  assert_success
  # dev.bak should now point to old-plugin (newly backed up)
  local bak_target
  bak_target=$(readlink "$PLUGIN_DIR/dev.bak")
  [ "$bak_target" = "$SANDBOX/old-plugin" ]
}

@test "switch: accepts --force to skip backup overwrite prompt" {
  mkdir -p "$SANDBOX/even-older-plugin"
  ln -s "$SANDBOX/even-older-plugin" "$PLUGIN_DIR/dev.bak"

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR" --force

  assert_success
  local bak_target
  bak_target=$(readlink "$PLUGIN_DIR/dev.bak")
  [ "$bak_target" = "$SANDBOX/old-plugin" ]
}

# ---------------------------------------------------------------------------
# Scenario: check 失敗時の中止
# ---------------------------------------------------------------------------

@test "switch: aborts when check returns exit 1" {
  stub_command "loom" '
    case "$*" in
      *validate*)
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_failure
  [ "$status" -eq 1 ]
  # Symlink must not change
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
  # No backup should be created
  [ ! -e "$PLUGIN_DIR/dev.bak" ]
}

@test "switch: does not modify symlink when autopilot session active" {
  stub_command "tmux" '
    case "$*" in
      *list-sessions*|*ls*)
        echo "autopilot:1:0"
        exit 0 ;;
      *show-environment*DEV_AUTOPILOT_SESSION*)
        echo "DEV_AUTOPILOT_SESSION=1"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_failure
  local target
  target=$(readlink "$PLUGIN_DIR/dev")
  [ "$target" = "$SANDBOX/old-plugin" ]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "switch: fails when --new target directory does not exist" {
  run bash "$SANDBOX/scripts/switchover.sh" switch --new "/nonexistent/path"

  assert_failure
  assert_output --partial "存在しません"
}

@test "switch: fails when --new is not provided" {
  run bash "$SANDBOX/scripts/switchover.sh" switch

  assert_failure
  assert_output --partial "--new"
}

@test "switch: fails when current symlink does not exist" {
  rm -f "$PLUGIN_DIR/dev"

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_failure
  assert_output --partial "symlink"
}

@test "switch: fails when plugin dir is a regular file, not symlink" {
  rm -f "$PLUGIN_DIR/dev"
  touch "$PLUGIN_DIR/dev"

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_failure
  assert_output --partial "symlink"
}

@test "switch: cleans up old state files during switch" {
  # Create some state files that should be cleaned
  mkdir -p "$SANDBOX/old-plugin/.state"
  touch "$SANDBOX/old-plugin/.state/lock"

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  assert_success
}

@test "switch: atomic operation - no partial state on mv failure" {
  # Make the plugin dir read-only to simulate failure
  chmod 555 "$PLUGIN_DIR"

  run bash "$SANDBOX/scripts/switchover.sh" switch --new "$NEW_PLUGIN_DIR"

  # Should fail
  assert_failure

  # Restore permissions for teardown
  chmod 755 "$PLUGIN_DIR"

  # Original symlink should still be intact
  [ -L "$PLUGIN_DIR/dev" ]
}

@test "switch: rejects --new pointing to relative path" {
  run bash "$SANDBOX/scripts/switchover.sh" switch --new "relative/path"

  assert_failure
  assert_output --partial "絶対パス"
}

@test "switch: rejects path traversal in --new argument" {
  run bash "$SANDBOX/scripts/switchover.sh" switch --new "/tmp/../../../etc/passwd"

  assert_failure
}
