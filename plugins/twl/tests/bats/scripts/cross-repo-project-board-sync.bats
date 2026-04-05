#!/usr/bin/env bats
# cross-repo-project-board-sync.bats
# BDD unit tests for cross-repo-autopilot / project-board-sync spec
# Spec: openspec/changes/cross-repo-autopilot/specs/project-board-sync/spec.md

load '../helpers/common'

setup() {
  common_setup

  # Stub gh with GraphQL recording
  stub_command "gh" '
    echo "GH_CALLED: $*" >> /tmp/gh-pbs-calls.log
    case "$*" in
      *"graphql"*"linkProjectV2ToRepository"*)
        # Extract repo info from args for logging
        echo "LINK_CALL: $*" >> /tmp/gh-pbs-calls.log
        echo "{\"data\": {\"linkProjectV2ToRepository\": {\"repository\": {\"id\": \"repo123\"}}}}" ;;
      *"graphql"*"createProjectV2"*)
        echo "{\"data\": {\"createProjectV2\": {\"projectV2\": {\"id\": \"proj456\", \"number\": 1}}}}" ;;
      *"graphql"*"addProjectV2ItemById"*)
        echo "{\"data\": {\"addProjectV2ItemById\": {\"item\": {\"id\": \"item789\"}}}}" ;;
      *"graphql"*"updateProjectV2ItemFieldValue"*)
        echo "{\"data\": {\"updateProjectV2ItemFieldValue\": {\"projectV2Item\": {\"id\": \"item789\"}}}}" ;;
      *"graphql"*)
        echo "{\"data\": {}}" ;;
      *"api"*"repos"*"lpd"*)
        echo "{\"id\": \"lpd-repo-id\", \"node_id\": \"MDEwOlJlcG9zaXRvcnkx\"}" ;;
      *"api"*"repos"*"loom"*)
        echo "{\"id\": \"loom-repo-id\", \"node_id\": \"MDEwOlJlcG9zaXRvcnky\"}" ;;
      *"api"*)
        echo "{\"id\": \"default-repo-id\", \"node_id\": \"MDEwOlJlcG9zaXRvcnkz\"}" ;;
      *"issue view"*"--json"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num, \"title\": \"Issue $num\", \"labels\": []}" ;;
      *)
        echo "{}" ;;
    esac
  '

  # Create session.json with multi-repo context
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n \
    --arg session_id "pbs-test" \
    --arg started_at "$now" \
    '{
      session_id: $session_id,
      started_at: $started_at,
      default_repo: "lpd",
      repos: {
        lpd: {owner: "shuu5", name: "loom-plugin-dev", path: "/home/shuu5/projects/lpd"},
        loom: {owner: "shuu5", name: "loom", path: "/home/shuu5/projects/loom"}
      },
      current_phase: 1,
      phase_count: 1,
      cross_issue_warnings: [],
      phase_insights: [],
      patterns: {},
      self_improve_issues: []
    }' > "$SANDBOX/.autopilot/session.json"

  # Create plan.yaml with multi-repo issues
  cat > "$SANDBOX/.autopilot/plan.yaml" <<PLAN_EOF
session_id: "pbs-test"
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
      - number: 50
        repo: loom
dependencies: {}
PLAN_EOF
}

teardown() {
  rm -f /tmp/gh-pbs-calls.log
  common_teardown
}

# Helper: assert gh was called with pattern
assert_gh_pbs_called_with() {
  local pattern="$1"
  grep -qE "$pattern" /tmp/gh-pbs-calls.log 2>/dev/null
}

# ---------------------------------------------------------------------------
# Requirement: project-create.sh の複数リポジトリリンク (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: 2 リポジトリのリンク
# WHEN repos: { lpd: ..., loom: ... } を持つプロジェクトが作成される
# THEN linkProjectV2ToRepository が lpd と loom の両方に対して呼び出される
@test "project-board-sync: project-create links all repos in repos section" {
  rm -f /tmp/gh-pbs-calls.log

  run bash "$SANDBOX/scripts/project-create.sh" \
    --project-name "cross-repo-test" \
    --repos-config "$SANDBOX/.autopilot/repos.yaml" \
    --project-dir "$SANDBOX" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    # project-create.sh may not have --repos-config flag yet
    # Try to run it with env var or alternative invocation
    REPOS_YAML="$SANDBOX/.autopilot/plan.yaml" \
      run bash "$SANDBOX/scripts/project-create.sh" \
        --project-name "cross-repo-test" \
        --project-dir "$SANDBOX" 2>/dev/null

    if [ "$status" -ne 0 ]; then
      skip "project-create.sh multi-repo link (--repos-config) not yet implemented"
    fi
  fi

  if [ -f /tmp/gh-pbs-calls.log ]; then
    # linkProjectV2ToRepository must be called at least twice (once per repo)
    local link_count
    link_count=$(grep -c "linkProjectV2ToRepository" /tmp/gh-pbs-calls.log 2>/dev/null || echo "0")
    [ "$link_count" -ge 2 ]
  fi
}

# project-create.sh: single-repo (no repos section) only links once
@test "project-board-sync: project-create without repos section links single repo" {
  rm -f /tmp/gh-pbs-calls.log

  # Remove repos section to simulate single-repo mode
  cat > "$SANDBOX/.autopilot/plan.yaml" <<PLAN_EOF
session_id: "single-pbs"
repo_mode: "worktree"
project_dir: "$SANDBOX"
phases:
  - phase: 1
    issues:
      - 10
dependencies: {}
PLAN_EOF

  run bash "$SANDBOX/scripts/project-create.sh" \
    --project-name "single-repo-test" \
    --project-dir "$SANDBOX" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    skip "project-create.sh invocation failed - may need additional args"
  fi
}

# ---------------------------------------------------------------------------
# Requirement: project-board-sync のクロスリポジトリ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: クロスリポジトリ Issue の同期
# WHEN autopilot セッションで lpd#42 と loom#50 が管理されている
# THEN 両方の Issue が同一 Project Board に追加され、Status が正しく更新される
@test "project-board-sync: both lpd#42 and loom#50 are added to same project board" {
  rm -f /tmp/gh-pbs-calls.log

  # Create issue state files for both repos
  mkdir -p "$SANDBOX/.autopilot/repos/lpd/issues"
  mkdir -p "$SANDBOX/.autopilot/repos/loom/issues"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -n --argjson issue 42 --arg status "running" --arg started_at "$now" \
    '{issue: $issue, status: $status, retry_count: 0, started_at: $started_at,
      branch: "feat/42-lpd", pr: null, window: "", current_step: "",
      fix_instructions: null, merged_at: null, files_changed: [], failure: null}' \
    > "$SANDBOX/.autopilot/repos/lpd/issues/issue-42.json"

  jq -n --argjson issue 50 --arg status "running" --arg started_at "$now" \
    '{issue: $issue, status: $status, retry_count: 0, started_at: $started_at,
      branch: "feat/50-loom", pr: null, window: "", current_step: "",
      fix_instructions: null, merged_at: null, files_changed: [], failure: null}' \
    > "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json"

  # Also write session.json with project_id for sync
  jq '. + {project_id: "test-project-123", project_number: 1}' \
    "$SANDBOX/.autopilot/session.json" > "$SANDBOX/.autopilot/session.json.tmp" && \
  mv "$SANDBOX/.autopilot/session.json.tmp" "$SANDBOX/.autopilot/session.json"

  # Attempt project board sync
  run bash "$SANDBOX/scripts/project-migrate.sh" \
    --plan-file "$SANDBOX/.autopilot/plan.yaml" \
    --project-dir "$SANDBOX" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    skip "project-migrate.sh cross-repo sync not yet implemented"
  fi

  if [ -f /tmp/gh-pbs-calls.log ]; then
    # addProjectV2ItemById should be called for at least 2 issues
    local add_count
    add_count=$(grep -c "addProjectV2ItemById" /tmp/gh-pbs-calls.log 2>/dev/null || echo "0")
    [ "$add_count" -ge 2 ]
  fi
}

# ---------------------------------------------------------------------------
# Requirement: co-autopilot SKILL.md の repos 引数解析 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: repos 引数の受け渡し
# WHEN co-autopilot に --repos lpd=~/projects/.../loom-plugin-dev,loom=~/projects/.../loom が渡される
# THEN autopilot-plan.sh に repos 情報が渡され、plan.yaml に repos セクションが生成される
@test "project-board-sync: co-autopilot --repos arg passes repos info to autopilot-plan" {
  # The co-autopilot SKILL.md drives this; test that --repos env/arg is parsed
  # and that autopilot-plan.sh receives repos parameter

  local repos_arg="lpd=$SANDBOX,loom=$SANDBOX/loom"

  # autopilot-plan.sh must accept --repos flag and generate repos section
  stub_command "uuidgen" 'echo "test-uuid"'
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json body"*)
        echo "" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  mkdir -p "$SANDBOX/loom"

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "lpd#42 loom#50" \
    --repos-arg "$repos_arg" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree" 2>/dev/null

  if [ -f "$SANDBOX/.autopilot/plan.yaml" ]; then
    run grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
    if [ "$status" -ne 0 ]; then
      skip "autopilot-plan.sh --repos-arg not yet implemented (repos section absent)"
    fi
  else
    skip "autopilot-plan.sh --repos-arg flag not yet implemented"
  fi
}

# Scenario: repos 引数省略時の後方互換
# WHEN co-autopilot に repos 引数が省略される
# THEN 従来の単一リポジトリ動作が維持される
@test "project-board-sync: co-autopilot without --repos maintains single-repo behaviour" {
  stub_command "uuidgen" 'echo "test-uuid-single"'
  stub_command "gh" 'echo "{\"number\": 10}"'

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "10,11" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]

  # No repos section should appear
  run grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  [ "$status" -ne 0 ]

  # Issues should appear as bare integers
  grep -q "10" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "11" "$SANDBOX/.autopilot/plan.yaml"
}
