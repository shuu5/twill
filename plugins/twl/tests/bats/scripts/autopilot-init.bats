#!/usr/bin/env bats
# autopilot-init.bats - unit tests for scripts/autopilot-init.sh

load '../helpers/common'

setup() {
  common_setup
  # Remove .autopilot dir so init can create it fresh
  rm -rf "$SANDBOX/.autopilot"
  # Set AUTOPILOT_DIR to sandbox
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-init
# ---------------------------------------------------------------------------

@test "autopilot-init creates .autopilot directory structure" {
  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  assert_output --partial "OK"
  [ -d "$SANDBOX/.autopilot" ]
  [ -d "$SANDBOX/.autopilot/issues" ]
  [ -d "$SANDBOX/.autopilot/archive" ]
}

@test "autopilot-init adds .autopilot/ to .gitignore" {
  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  grep -qxF '.autopilot/' "$SANDBOX/.gitignore"
}

@test "autopilot-init does not duplicate .gitignore entry" {
  echo '.autopilot/' > "$SANDBOX/.gitignore"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  local count
  count=$(grep -cxF '.autopilot/' "$SANDBOX/.gitignore")
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Session exclusivity
# ---------------------------------------------------------------------------

@test "autopilot-init fails when active session exists (< 24h)" {
  mkdir -p "$SANDBOX/.autopilot"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "active123", "started_at": "$now"}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "既存セッションが実行中"
}

@test "autopilot-init warns about stale session (>= 24h) without --force" {
  mkdir -p "$SANDBOX/.autopilot"
  local old_date
  old_date=$(date -u -d '2 days ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-2d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "stale999", "started_at": "$old_date"}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "stale"
}

@test "autopilot-init --force removes stale session" {
  mkdir -p "$SANDBOX/.autopilot"
  local old_date
  old_date=$(date -u -d '2 days ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-2d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "stale999", "started_at": "$old_date", "issues": [{"issue": 1, "status": "running"}]}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_success
  assert_output --partial "stale セッション"
  [ ! -f "$SANDBOX/.autopilot/session.json" ]
}

@test "autopilot-init --check-only verifies no active session" {
  run bash "$SANDBOX/scripts/autopilot-init.sh" --check-only

  assert_success
  assert_output --partial "OK"
  # --check-only should not create directory
  [ ! -d "$SANDBOX/.autopilot/issues" ] || true
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "autopilot-init uses atomic lock (mkdir)" {
  # Create lock manually to simulate concurrent init
  mkdir -p "$SANDBOX/.autopilot"
  mkdir -p "$SANDBOX/.autopilot/.lock"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  assert_output --partial "別のプロセスが初期化中"

  # Clean up for teardown
  rmdir "$SANDBOX/.autopilot/.lock" 2>/dev/null || true
}

@test "autopilot-init fails with unknown option" {
  run bash "$SANDBOX/scripts/autopilot-init.sh" --unknown

  assert_failure
  assert_output --partial "不明なオプション"
}

# ---------------------------------------------------------------------------
# Requirement: 完了済みセッションの --force 削除 (stale-session-force-delete)
# ---------------------------------------------------------------------------

@test "all issues done + --force + under 24h: deletes session and continues init" {
  mkdir -p "$SANDBOX/.autopilot"
  local started_at
  started_at=$(date -u -d '20 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "done1234",
  "started_at": "$started_at",
  "issues": [
    {"issue": 1, "status": "done"},
    {"issue": 2, "status": "done"}
  ]
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_success
  [ ! -f "$SANDBOX/.autopilot/session.json" ]
}

@test "all issues done + --force + over 24h: deletes session and continues init" {
  mkdir -p "$SANDBOX/.autopilot"
  local started_at
  started_at=$(date -u -d '30 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "done5678",
  "started_at": "$started_at",
  "issues": [
    {"issue": 1, "status": "done"},
    {"issue": 2, "status": "done"}
  ]
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_success
  [ ! -f "$SANDBOX/.autopilot/session.json" ]
}

@test "running issue + --force + under 24h: blocks with exit 1" {
  mkdir -p "$SANDBOX/.autopilot"
  local started_at
  started_at=$(date -u -d '20 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "run1234",
  "started_at": "$started_at",
  "issues": [
    {"issue": 1, "status": "running"},
    {"issue": 2, "status": "done"}
  ]
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_failure
  [ "$status" -eq 1 ]
}

@test "running issue + --force + over 24h: treats as stale, deletes and continues" {
  mkdir -p "$SANDBOX/.autopilot"
  local started_at
  started_at=$(date -u -d '30 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "run5678",
  "started_at": "$started_at",
  "issues": [
    {"issue": 1, "status": "running"},
    {"issue": 2, "status": "done"}
  ]
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_success
  [ ! -f "$SANDBOX/.autopilot/session.json" ]
}

@test "issues field absent + --force: blocks with exit 1 (fail-closed, not treated as done)" {
  mkdir -p "$SANDBOX/.autopilot"
  local started_at
  started_at=$(date -u -d '20 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "noissues",
  "started_at": "$started_at"
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  assert_failure
  [ "$status" -eq 1 ]
  [ -f "$SANDBOX/.autopilot/session.json" ]
}

@test "running issue + no --force + under 24h: blocks with exit 1" {
  mkdir -p "$SANDBOX/.autopilot"
  local started_at
  started_at=$(date -u -d '20 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "active999",
  "started_at": "$started_at",
  "issues": [
    {"issue": 1, "status": "running"}
  ]
}
JSON

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_failure
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-init.md の eval 除去 (eval-removal)
# ---------------------------------------------------------------------------

@test "autopilot-init.md does not use eval for autopilot-init.sh execution" {
  local md_file="$REPO_ROOT/commands/autopilot-init.md"

  # The step that calls autopilot-init.sh must not use eval
  # We check that any line referencing autopilot-init.sh does not also contain eval
  local violations
  violations=$(grep 'autopilot-init\.sh' "$md_file" | grep 'eval' || true)

  [ -z "$violations" ]
}

@test "autopilot-init.md does not use eval for session-create.sh execution" {
  local md_file="$REPO_ROOT/commands/autopilot-init.md"

  # The step that calls session-create.sh must not use eval
  local violations
  violations=$(grep 'session-create\.sh' "$md_file" | grep 'eval' || true)

  [ -z "$violations" ]
}
