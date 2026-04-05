#!/usr/bin/env bats
# autopilotdir-state-split.bats - AUTOPILOT_DIR 統一による Pilot/Worker 状態一致テスト
# Issue #69: AUTOPILOT_DIR 三重不一致による Pilot/Worker 状態ファイル分断

load '../helpers/common'

setup() {
  common_setup
  rm -rf "$SANDBOX/.autopilot"
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: co-autopilot SKILL.md で AUTOPILOT_DIR を export する
# ---------------------------------------------------------------------------

# Scenario: bare repo 構成での AUTOPILOT_DIR 設定
@test "AUTOPILOT_DIR override: autopilot-init creates dirs at specified path" {
  export AUTOPILOT_DIR="$SANDBOX/custom-autopilot"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  [ -d "$SANDBOX/custom-autopilot" ]
  [ -d "$SANDBOX/custom-autopilot/issues" ]
  [ -d "$SANDBOX/custom-autopilot/archive" ]
}

# Scenario: standard repo 構成での AUTOPILOT_DIR 設定
@test "AUTOPILOT_DIR override: default fallback uses PROJECT_ROOT/.autopilot" {
  unset AUTOPILOT_DIR

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  [ -d "$SANDBOX/.autopilot" ]
  [ -d "$SANDBOX/.autopilot/issues" ]
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-init.md で AUTOPILOT_DIR を伝搬する
# ---------------------------------------------------------------------------

# Scenario: autopilot-init.sh への AUTOPILOT_DIR 伝搬
@test "autopilot-init respects AUTOPILOT_DIR for session-create" {
  export AUTOPILOT_DIR="$SANDBOX/pilot-dir"

  run bash "$SANDBOX/scripts/autopilot-init.sh"
  assert_success

  # session-create should use the same AUTOPILOT_DIR
  local plan_file="$SANDBOX/pilot-dir/plan.yaml"
  cat > "$plan_file" <<'YAML'
phases:
  - phase: 1
    issues:
    - 10
YAML

  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$plan_file" --phase-count 1

  assert_success
  [ -f "$SANDBOX/pilot-dir/session.json" ]
}

# Scenario: SESSION_STATE_FILE の統一
@test "session-create writes to AUTOPILOT_DIR/session.json not PROJECT_ROOT" {
  export AUTOPILOT_DIR="$SANDBOX/unified-dir"
  mkdir -p "$AUTOPILOT_DIR"

  local plan_file="$AUTOPILOT_DIR/plan.yaml"
  cat > "$plan_file" <<'YAML'
phases:
  - phase: 1
    issues:
    - 10
YAML

  run bash "$SANDBOX/scripts/session-create.sh" \
    --plan-path "$plan_file" --phase-count 1

  assert_success
  [ -f "$SANDBOX/unified-dir/session.json" ]
  # Must NOT create at default PROJECT_ROOT/.autopilot/
  [ ! -f "$SANDBOX/.autopilot/session.json" ]
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-phase-execute.md で AUTOPILOT_DIR を伝搬する
# ---------------------------------------------------------------------------

# Scenario: state-read.sh への AUTOPILOT_DIR 伝搬
@test "state-read uses AUTOPILOT_DIR to find issue state" {
  export AUTOPILOT_DIR="$SANDBOX/pilot-state"
  mkdir -p "$AUTOPILOT_DIR/issues"

  # Worker writes state to AUTOPILOT_DIR
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/issues/issue-42.json" <<JSON
{"issue": 42, "status": "merge-ready", "started_at": "$now", "retry_count": 0}
JSON

  # Pilot reads using same AUTOPILOT_DIR
  run python3 -m twl.autopilot.state read \
    --type issue --issue 42 --field status

  assert_success
  assert_output "merge-ready"
}

# Scenario: state-write.sh への AUTOPILOT_DIR 伝搬
@test "state-write uses AUTOPILOT_DIR to update issue state" {
  export AUTOPILOT_DIR="$SANDBOX/pilot-state"
  mkdir -p "$AUTOPILOT_DIR/issues"

  # Create initial state
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$AUTOPILOT_DIR/issues/issue-42.json" <<JSON
{"issue": 42, "status": "merge-ready", "branch": "", "pr": null, "window": "", "started_at": "$now", "current_step": "", "retry_count": 0, "fix_instructions": null, "merged_at": null, "files_changed": [], "failure": null}
JSON

  # Pilot updates state
  run python3 -m twl.autopilot.state write \
    --type issue --issue 42 --role pilot --set "status=done"

  assert_success

  # Verify state was written at AUTOPILOT_DIR, not default
  local result
  result=$(jq -r '.status' "$AUTOPILOT_DIR/issues/issue-42.json")
  [ "$result" = "done" ]
  [ ! -f "$SANDBOX/.autopilot/issues/issue-42.json" ]
}

# Scenario: Pilot と Worker の状態ファイル一致
@test "Pilot and Worker share same state file via AUTOPILOT_DIR" {
  export AUTOPILOT_DIR="$SANDBOX/shared-state"
  mkdir -p "$AUTOPILOT_DIR/issues"

  # Worker creates issue state (--init)
  run python3 -m twl.autopilot.state write \
    --type issue --issue 99 --role worker --init

  assert_success
  [ -f "$AUTOPILOT_DIR/issues/issue-99.json" ]

  # Worker updates to merge-ready
  run python3 -m twl.autopilot.state write \
    --type issue --issue 99 --role worker --set "status=merge-ready"
  assert_success

  # Pilot reads the same file
  run python3 -m twl.autopilot.state read \
    --type issue --issue 99 --field status

  assert_success
  assert_output "merge-ready"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "state-read returns empty for non-existent issue when AUTOPILOT_DIR set" {
  export AUTOPILOT_DIR="$SANDBOX/empty-state"
  mkdir -p "$AUTOPILOT_DIR/issues"

  run python3 -m twl.autopilot.state read \
    --type issue --issue 999 --field status

  assert_success
  assert_output ""
}

@test "AUTOPILOT_DIR with trailing slash is handled correctly" {
  export AUTOPILOT_DIR="$SANDBOX/trail-slash/"
  mkdir -p "$SANDBOX/trail-slash/issues"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/trail-slash/issues/issue-1.json" <<JSON
{"issue": 1, "status": "running", "started_at": "$now", "retry_count": 0}
JSON

  run python3 -m twl.autopilot.state read \
    --type issue --issue 1 --field status

  assert_success
  assert_output "running"
}
