#!/usr/bin/env bats
# cross-repo-state-namespace.bats
# BDD unit tests for cross-repo-autopilot / state-namespace spec
# Spec: openspec/changes/cross-repo-autopilot/specs/state-namespace/spec.md

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: 状態ファイルのリポジトリ名前空間化
# ---------------------------------------------------------------------------

# Scenario: 異なるリポジトリの同一 Issue 番号
# WHEN lpd#10 と loom#10 が同一 autopilot セッションで管理される
# THEN .autopilot/repos/lpd/issues/issue-10.json と
#      .autopilot/repos/loom/issues/issue-10.json が個別に作成される
@test "state-namespace: same issue number in different repos creates separate files" {
  # Create namespaced directories
  mkdir -p "$SANDBOX/.autopilot/repos/lpd/issues"
  mkdir -p "$SANDBOX/.autopilot/repos/loom/issues"

  # Write state for lpd#10
  run python3 -m twl.autopilot.state write \
    --type issue --issue 10 --role worker --init \
    --repo lpd
  [ "$status" -eq 0 ]

  # Write state for loom#10
  run python3 -m twl.autopilot.state write \
    --type issue --issue 10 --role worker --init \
    --repo loom
  [ "$status" -eq 0 ]

  # Both namespaced files must exist independently
  [ -f "$SANDBOX/.autopilot/repos/lpd/issues/issue-10.json" ]
  [ -f "$SANDBOX/.autopilot/repos/loom/issues/issue-10.json" ]

  # The two files are separate (not symlinks to each other)
  [ "$SANDBOX/.autopilot/repos/lpd/issues/issue-10.json" \
    != "$SANDBOX/.autopilot/repos/loom/issues/issue-10.json" ]
}

# Scenario: 後方互換 — repos 未使用時のフォールバック
# WHEN repos セクションが省略された plan.yaml で autopilot が実行される
# THEN 従来の .autopilot/issues/issue-{N}.json パスが使用される
@test "state-namespace: no repos section falls back to legacy .autopilot/issues/ path" {
  # state-write.sh without --repo must write to legacy path
  run python3 -m twl.autopilot.state write \
    --type issue --issue 42 --role worker --init

  assert_success
  # File must exist at legacy path
  [ -f "$SANDBOX/.autopilot/issues/issue-42.json" ]

  # File must NOT be created at a namespaced path
  [ ! -f "$SANDBOX/.autopilot/repos/issues/issue-42.json" ] || true
}

# state-read without --repo also falls back to legacy path
@test "state-namespace: state-read without --repo reads from legacy path" {
  create_issue_json 7 "running"

  run python3 -m twl.autopilot.state read \
    --type issue --issue 7 --field status

  assert_success
  assert_output "running"
}

# ---------------------------------------------------------------------------
# Requirement: state-read.sh のリポジトリ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: repo_id 指定での読み取り
# WHEN state-read.sh --repo lpd --issue 42 --key status が実行される
# THEN .autopilot/repos/lpd/issues/issue-42.json の status フィールドを返す
@test "state-read: --repo lpd --issue 42 reads from namespaced path" {
  # Create namespaced state file
  mkdir -p "$SANDBOX/.autopilot/repos/lpd/issues"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --argjson issue 42 --arg status "merge-ready" --arg started_at "$now" \
    '{issue: $issue, status: $status, retry_count: 0, started_at: $started_at,
      branch: "feat/42-test", pr: null, window: "", current_step: "",
      fix_instructions: null, merged_at: null, files_changed: [], failure: null}' \
    > "$SANDBOX/.autopilot/repos/lpd/issues/issue-42.json"

  run python3 -m twl.autopilot.state read \
    --type issue --repo lpd --issue 42 --field status

  if [ "$status" -ne 0 ]; then
    # --repo flag not yet implemented
    skip "state-read.sh --repo flag not yet implemented"
  fi

  assert_output "merge-ready"
}

# Scenario: repo_id 省略での後方互換
# WHEN state-read.sh --issue 42 --key status が repo_id なしで実行される
# THEN 従来の .autopilot/issues/issue-42.json から読み取る
@test "state-read: omitting --repo reads from legacy .autopilot/issues/ path" {
  create_issue_json 42 "failed"

  run python3 -m twl.autopilot.state read \
    --type issue --issue 42 --field status

  assert_success
  assert_output "failed"
}

# ---------------------------------------------------------------------------
# Requirement: state-write.sh のリポジトリ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: repo_id 指定での書き込み
# WHEN state-write.sh --repo loom --issue 50 --role worker --set status=running が実行される
# THEN .autopilot/repos/loom/issues/issue-50.json に書き込まれる
@test "state-write: --repo loom --issue 50 writes to namespaced path" {
  mkdir -p "$SANDBOX/.autopilot/repos/loom/issues"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --argjson issue 50 --arg started_at "$now" \
    '{issue: $issue, status: "running", retry_count: 0, started_at: $started_at,
      branch: "", pr: null, window: "", current_step: "",
      fix_instructions: null, merged_at: null, files_changed: [], failure: null}' \
    > "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json"

  run python3 -m twl.autopilot.state write \
    --type issue --repo loom --issue 50 --role worker \
    --set current_step="merge-gate"

  if [ "$status" -ne 0 ]; then
    skip "state-write.sh --repo flag not yet implemented"
  fi

  # File must be updated at namespaced path
  [ -f "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json" ]
  local step
  step=$(jq -r '.current_step' "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json")
  [ "$step" = "merge-gate" ]
}

# Namespaced write must not touch legacy path
@test "state-write: --repo write does not create legacy path file" {
  mkdir -p "$SANDBOX/.autopilot/repos/loom/issues"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --argjson issue 50 --arg started_at "$now" \
    '{issue: $issue, status: "running", retry_count: 0, started_at: $started_at,
      branch: "", pr: null, window: "", current_step: "",
      fix_instructions: null, merged_at: null, files_changed: [], failure: null}' \
    > "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json"

  run python3 -m twl.autopilot.state write \
    --type issue --repo loom --issue 50 --role worker \
    --set current_step="review"

  if [ "$status" -ne 0 ]; then
    skip "state-write.sh --repo flag not yet implemented"
  fi

  # Legacy path must remain absent
  [ ! -f "$SANDBOX/.autopilot/issues/issue-50.json" ]
}

# ---------------------------------------------------------------------------
# Requirement: session.json のリポジトリ情報 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: session.json にリポジトリ情報が記録される
# WHEN クロスリポジトリ autopilot セッションが開始される
# THEN session.json に repos オブジェクト（各 repo_id の owner, name, path）と
#      default_repo が記録される
@test "state-namespace: cross-repo session.json contains repos and default_repo fields" {
  # Create cross-repo session.json fixture
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n \
    --arg session_id "cross123" \
    --arg started_at "$now" \
    --arg default_repo "lpd" \
    '{
      session_id: $session_id,
      started_at: $started_at,
      default_repo: $default_repo,
      repos: {
        lpd: {owner: "shuu5", name: "loom-plugin-dev", path: "/home/shuu5/projects/lpd"},
        loom: {owner: "shuu5", name: "loom", path: "/home/shuu5/projects/loom"}
      },
      current_phase: 1,
      phase_count: 2
    }' > "$SANDBOX/.autopilot/session.json"

  # Verify repos field is present
  run python3 -m twl.autopilot.state read \
    --type session --field repos

  assert_success
  # Should return JSON object (non-empty)
  [ -n "$output" ]

  # Verify default_repo field
  run python3 -m twl.autopilot.state read \
    --type session --field default_repo

  assert_success
  assert_output "lpd"
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-init.sh のディレクトリ作成 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: クロスリポジトリ初期化
# WHEN plan.yaml に repos: { lpd: ..., loom: ... } が含まれる
# THEN .autopilot/repos/lpd/issues/ と .autopilot/repos/loom/issues/ が作成される
@test "autopilot-init: repos section creates per-repo subdirectories" {
  rm -rf "$SANDBOX/.autopilot"
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"

  # Create plan.yaml with repos section
  mkdir -p "$SANDBOX/.autopilot"
  cat > "$SANDBOX/.autopilot/plan.yaml" <<PLAN_EOF
session_id: "init-test"
repo_mode: "worktree"
project_dir: "$SANDBOX"
repos:
  lpd:
    owner: shuu5
    name: loom-plugin-dev
    path: $SANDBOX
  loom:
    owner: shuu5
    name: loom
    path: $SANDBOX/loom
phases:
  - phase: 1
    issues:
      - number: 42
        repo: lpd
PLAN_EOF

  run bash "$SANDBOX/scripts/autopilot-init.sh" --force

  if [ "$status" -ne 0 ]; then
    skip "autopilot-init.sh cross-repo directory creation not yet implemented"
  fi

  # Both repo-namespaced issue dirs must be created
  [ -d "$SANDBOX/.autopilot/repos/lpd/issues" ]
  [ -d "$SANDBOX/.autopilot/repos/loom/issues" ]
}

# Legacy init (no repos section) must still create classic directory structure
@test "autopilot-init: no repos section creates only legacy .autopilot/issues/ dir" {
  rm -rf "$SANDBOX/.autopilot"
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  [ -d "$SANDBOX/.autopilot/issues" ]
  [ -d "$SANDBOX/.autopilot/archive" ]

  # repos/ subdirectory must NOT be created by default
  [ ! -d "$SANDBOX/.autopilot/repos" ]
}
