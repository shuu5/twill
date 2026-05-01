#!/usr/bin/env bash
# common.bash - shared setup/teardown and utilities for bats tests

# Resolve paths relative to this helper
HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_TEST_DIR="$(cd "$HELPERS_DIR/.." && pwd)"
TESTS_DIR="$(cd "$BATS_TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Load bats libraries
load "${TESTS_DIR}/lib/bats-support/load"
load "${TESTS_DIR}/lib/bats-assert/load"

# ---------------------------------------------------------------------------
# Sandbox management
# ---------------------------------------------------------------------------

# common_setup: create a tmpdir sandbox, copy scripts, set PATH
common_setup() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX

  # Save original PATH for teardown restoration
  _ORIGINAL_PATH="$PATH"

  # Mirror minimal project structure inside sandbox
  mkdir -p "$SANDBOX/scripts"
  mkdir -p "$SANDBOX/.autopilot/issues"
  mkdir -p "$SANDBOX/.autopilot/archive"

  # Copy all scripts into sandbox
  cp "$REPO_ROOT"/scripts/*.sh "$SANDBOX/scripts/" 2>/dev/null || true
  cp "$REPO_ROOT"/scripts/*.py "$SANDBOX/scripts/" 2>/dev/null || true
  # Copy scripts/lib/* (sourced by chain-runner.sh, project-board-archive.sh, pr-create-helper.sh, etc.)
  if [[ -d "$REPO_ROOT/scripts/lib" ]]; then
    mkdir -p "$SANDBOX/scripts/lib"
    cp -r "$REPO_ROOT/scripts/lib/." "$SANDBOX/scripts/lib/" 2>/dev/null || true
  fi

  # Copy Python autopilot modules (replaces state/session bash scripts)
  local _repo_git_root
  _repo_git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null || echo "")"
  if [[ -n "$_repo_git_root" && -d "$_repo_git_root/cli/twl/src" ]]; then
    export PYTHONPATH="${_repo_git_root}/cli/twl/src${PYTHONPATH:+:${PYTHONPATH}}"
  fi

  # Create a stub bin directory for external command stubs
  STUB_BIN="$SANDBOX/.stub-bin"
  mkdir -p "$STUB_BIN"
  export STUB_BIN

  # Prepend stub bin to PATH so stubs override real commands
  export PATH="$STUB_BIN:$PATH"

  # Set PROJECT_ROOT for scripts that derive paths from SCRIPT_DIR
  # We symlink scripts so SCRIPT_DIR/../ resolves to SANDBOX
  export PROJECT_ROOT="$SANDBOX"

  # Also set AUTOPILOT_DIR override for scripts that support it
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
}

# common_teardown: remove the sandbox directory
common_teardown() {
  # Restore original PATH to prevent inter-test pollution
  if [[ -n "${_ORIGINAL_PATH:-}" ]]; then
    export PATH="$_ORIGINAL_PATH"
  fi
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}

# ---------------------------------------------------------------------------
# Stub utilities
# ---------------------------------------------------------------------------

# stub_command <name> <body>
# Creates an executable stub in STUB_BIN that executes <body>.
# Example: stub_command "gh" 'echo "mocked gh output"'
stub_command() {
  local name="$1"
  local body="${2:-exit 0}"

  cat > "$STUB_BIN/$name" <<STUB_EOF
#!/usr/bin/env bash
$body
STUB_EOF
  chmod +x "$STUB_BIN/$name"
}

# stub_command_with_args <name> <expected_args_pattern> <matching_body> <fallback_body>
# Creates a stub that checks arguments against a pattern.
stub_command_with_args() {
  local name="$1"
  local pattern="$2"
  local match_body="$3"
  local fallback_body="${4:-exit 0}"

  cat > "$STUB_BIN/$name" <<STUB_EOF
#!/usr/bin/env bash
if echo "\$*" | grep -qE "$pattern"; then
  $match_body
else
  $fallback_body
fi
STUB_EOF
  chmod +x "$STUB_BIN/$name"
}

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# create_issue_json <issue_number> <status> [extra_jq_args...]
# Creates a minimal issue-N.json in the sandbox .autopilot/issues/
create_issue_json() {
  local issue_num="$1"
  local status="$2"
  shift 2
  local file="$SANDBOX/.autopilot/issues/issue-${issue_num}.json"
  mkdir -p "$(dirname "$file")"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local base_json
  base_json=$(jq -n \
    --argjson issue "$issue_num" \
    --arg status "$status" \
    --arg started_at "$now" \
    '{
      issue: $issue,
      status: $status,
      branch: "feat/'"$issue_num"'-test",
      pr: null,
      window: "",
      started_at: $started_at,
      current_step: "",
      retry_count: 0,
      fix_instructions: null,
      merged_at: null,
      files_changed: [],
      failure: null
    }')

  # Apply extra jq modifications
  for arg in "$@"; do
    base_json=$(echo "$base_json" | jq "$arg")
  done

  echo "$base_json" > "$file"
}

# create_session_json [extra_jq_args...]
# Creates a minimal session.json in the sandbox
create_session_json() {
  local file="$SANDBOX/.autopilot/session.json"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local base_json
  base_json=$(jq -n \
    --arg session_id "test1234" \
    --arg started_at "$now" \
    '{
      session_id: $session_id,
      plan_path: ".autopilot/plan.yaml",
      current_phase: 1,
      phase_count: 2,
      started_at: $started_at,
      cross_issue_warnings: [],
      phase_insights: [],
      patterns: {},
      self_improve_issues: []
    }')

  for arg in "$@"; do
    base_json=$(echo "$base_json" | jq "$arg")
  done

  echo "$base_json" > "$file"
}

# create_plan_yaml <content>
# Write plan.yaml content to sandbox
create_plan_yaml() {
  local content="$1"
  echo "$content" > "$SANDBOX/.autopilot/plan.yaml"
}

# ---------------------------------------------------------------------------
# autopilot-launch test helpers (shared across autopilot-launch-*.bats)
# ---------------------------------------------------------------------------

# extracted from: autopilot-launch-merge-context.bats, autopilot-launch-snapshot-dir.bats, autopilot-launch-autopilotdir.bats
_get_tmux_cmd() {
  cat "$TMUX_CMD_FILE" 2>/dev/null || echo ""
}

# extracted from: autopilot-launch-merge-context.bats, autopilot-launch-snapshot-dir.bats, autopilot-launch-autopilotdir.bats
_tmux_cmd_contains() {
  local keyword="$1"
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  echo "$tmux_cmd" | tr -d '\\' | grep -qF "$keyword"
}

# extracted from: autopilot-launch-merge-context.bats, autopilot-launch-snapshot-dir.bats
_run_launch() {
  local issue="${1:-42}"
  local extra_args="${2:-}"
  # shellcheck disable=SC2086
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue "$issue" \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "$SANDBOX/.autopilot" \
    $extra_args
}

