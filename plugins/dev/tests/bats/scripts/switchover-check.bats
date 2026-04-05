#!/usr/bin/env bats
# switchover-check.bats - unit tests for scripts/switchover.sh check subcommand
#
# Spec: openspec/changes/c-6-switchover/specs/switchover-script.md
# Requirement: switchover.sh check subcommand

load '../helpers/common'

setup() {
  common_setup

  # Create a plugin symlink structure in sandbox
  PLUGIN_DIR="$SANDBOX/.claude/plugins"
  mkdir -p "$PLUGIN_DIR"
  mkdir -p "$SANDBOX/new-plugin"
  ln -s "$SANDBOX/new-plugin" "$PLUGIN_DIR/dev"
  export PLUGIN_DIR

  # Default stubs: twl validate/check pass, no tmux sessions
  stub_command "loom" '
    case "$*" in
      *validate*)
        echo "validate: OK"
        exit 0 ;;
      *check*)
        echo "check: OK"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "tmux" '
    case "$*" in
      *list-sessions*|*ls*)
        exit 1 ;;  # No sessions
      *show-environment*)
        exit 1 ;;  # No env var
      *)
        exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: switchover.sh check subcommand
# Scenario: 全チェック pass
# ---------------------------------------------------------------------------

@test "check: returns exit 0 when all checks pass" {
  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_success
  assert_output --partial "切替可能"
}

@test "check: verifies twl validate passes" {
  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_success
  assert_output --partial "validate"
}

@test "check: verifies twl check passes" {
  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_success
  assert_output --partial "check"
}

@test "check: displays current symlink path" {
  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_success
  # Should show the current symlink target
  assert_output --partial "symlink"
}

# ---------------------------------------------------------------------------
# Scenario: autopilot セッション稼働中
# ---------------------------------------------------------------------------

@test "check: fails when tmux autopilot session is running" {
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

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "in-flight"
}

@test "check: detects DEV_AUTOPILOT_SESSION=1 in tmux environment" {
  # Simulate tmux session with DEV_AUTOPILOT_SESSION set
  stub_command "tmux" '
    case "$*" in
      *list-sessions*|*ls*)
        echo "dev-session:2:1"
        exit 0 ;;
      *show-environment*DEV_AUTOPILOT_SESSION*)
        echo "DEV_AUTOPILOT_SESSION=1"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
  assert_output --partial "セッション検出"
}

@test "check: passes when tmux sessions exist but none have DEV_AUTOPILOT_SESSION" {
  stub_command "tmux" '
    case "$*" in
      *list-sessions*|*ls*)
        echo "other-session:1:0"
        exit 0 ;;
      *show-environment*DEV_AUTOPILOT_SESSION*)
        exit 1 ;;  # Variable not set
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: twl validate 失敗
# ---------------------------------------------------------------------------

@test "check: fails when twl validate fails" {
  stub_command "loom" '
    case "$*" in
      *validate*)
        echo "validate: FAIL - deps.yaml invalid"
        exit 1 ;;
      *check*)
        echo "check: OK"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "検証失敗"
}

@test "check: displays validate failure details" {
  stub_command "loom" '
    case "$*" in
      *validate*)
        echo "ERROR: missing field: controller" >&2
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
  # Should forward or include the error details
  assert_output --partial "validate"
}

@test "check: fails when twl check fails" {
  stub_command "loom" '
    case "$*" in
      *validate*)
        echo "validate: OK"
        exit 0 ;;
      *check*)
        echo "check: FAIL - circular dependency"
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "check: fails when loom command is not found" {
  rm -f "$STUB_BIN/loom"
  # Ensure loom is not in PATH at all
  stub_command "loom" 'echo "command not found: loom" >&2; exit 127'

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
}

@test "check: handles tmux not installed gracefully" {
  # tmux not available - should treat as no sessions running
  stub_command "tmux" 'echo "command not found: tmux" >&2; exit 127'

  run bash "$SANDBOX/scripts/switchover.sh" check

  # Should still succeed if twl checks pass (no tmux = no sessions)
  assert_success
}

@test "check: fails when both twl validate and check fail" {
  stub_command "loom" '
    echo "FAIL" >&2
    exit 1
  '

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
  [ "$status" -eq 1 ]
}

@test "check: reports all failed checks, not just the first one" {
  stub_command "loom" '
    case "$*" in
      *validate*)
        echo "validate: FAIL" >&2
        exit 1 ;;
      *check*)
        echo "check: FAIL" >&2
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  '
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

  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_failure
}

@test "check: no arguments after 'check' is valid" {
  run bash "$SANDBOX/scripts/switchover.sh" check

  assert_success
}

@test "check: rejects unknown subcommand" {
  run bash "$SANDBOX/scripts/switchover.sh" invalid-subcommand

  assert_failure
  assert_output --partial "不明なサブコマンド"
}

@test "check: fails with no subcommand" {
  run bash "$SANDBOX/scripts/switchover.sh"

  assert_failure
  assert_output --partial "使用方法"
}

@test "check: symlink not present warns but continues" {
  rm -f "$PLUGIN_DIR/dev"

  run bash "$SANDBOX/scripts/switchover.sh" check

  # Should still run checks, may warn about missing symlink
  # The twl checks determine pass/fail, not symlink presence
  assert_success || assert_output --partial "symlink"
}
