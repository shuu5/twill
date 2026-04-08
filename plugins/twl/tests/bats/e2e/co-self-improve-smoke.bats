#!/usr/bin/env bats
# co-self-improve-smoke.bats
# E2E smoke tests for co-self-improve framework (子 8 / Issue #180)
#
# Tests the full integration: test-project-init → scenario-load → observe →
# problem-detect → workflow-observe-loop → issue-draft
#
# Depends on child issues being merged:
#   子 3 (#175): test-project-{init,reset,scenario-load} atomic commands
#   子 4 (#176): observe-once + problem-detect + issue-draft-from-observation
#   子 5 (#177): workflow-observe-loop + observe-and-detect
#   子 6 (#178): observer-evaluator specialist + parser
#   子 7 (#179): reference files (test-scenario-catalog, observation-pattern-catalog, load-test-baselines)
#
# When any dependency is not yet merged, the test is skipped via bats `skip`.
# Run: bats plugins/twl/tests/bats/e2e/co-self-improve-smoke.bats
# Expected execution time: under 5 minutes
#
# BATS_TEST_TIMEOUT is set per-test via bats options; use --timeout 300 when running.

load '../helpers/common'
load '../helpers/git-fixture'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Resolve the path to a co-self-improve command script.
# Commands are shell scripts at $REPO_ROOT/scripts/co-self-improve/<name>.sh
# Once 子 3-7 are merged, these scripts will exist.
_cmd_path() {
  local name="$1"
  # Commands may be implemented as scripts under scripts/ or commands/
  # Check both locations
  local p1="$REPO_ROOT/scripts/co-self-improve/${name}.sh"
  local p2="$REPO_ROOT/commands/${name}.sh"
  if [[ -f "$p1" ]]; then echo "$p1"
  elif [[ -f "$p2" ]]; then echo "$p2"
  else echo ""
  fi
}

# _require_cmd <name>: skip the test if command is not yet implemented
_require_cmd() {
  local name="$1"
  local path
  path=$(_cmd_path "$name")
  if [[ -z "$path" ]]; then
    skip "Command '${name}' not yet implemented (depends on 子 3-7)"
  fi
  echo "$path"
}

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # Create an isolated temporary git repo for worktree tests
  TMP_REPO=$(init_temp_repo)
  export TMP_REPO

  # Reference to plugin root (set by common_setup via REPO_ROOT)
  PLUGIN_DIR="$REPO_ROOT"
  export PLUGIN_DIR
}

teardown() {
  cleanup_temp_repo "$TMP_REPO"
  common_teardown
}

# ---------------------------------------------------------------------------
# Smoke tests (7 cases)
# ---------------------------------------------------------------------------

# Scenario: test-project-init creates orphan worktree
# WHEN test-project-init is executed in a git repo
# THEN worktrees/test-target/ is created as an orphan branch with no common ancestor to main
@test "smoke: test-project-init creates orphan worktree" {
  _require_cmd "test-project-init"
  local cmd
  cmd=$(_cmd_path "test-project-init")

  run bash "$cmd" --auto-confirm
  assert_success

  [ -d "$TMP_REPO/worktrees/test-target" ]
  [ "$(cd "$TMP_REPO" && git worktree list | grep -c test-target)" -eq 1 ]

  # MUST: 隔離保証 — main と test-target/main に共通 commit が無い (orphan branch)
  run verify_orphan_branch "main" "test-target/main" "$TMP_REPO"
  assert_success
}

# Scenario: scenario-load smoke-001 creates dummy issue file
# WHEN test-project-scenario-load --scenario smoke-001 is executed
# THEN worktrees/test-target/.test-target/issues/smoke-001.md is created with "hello"
@test "smoke: scenario-load smoke-001 creates dummy issue file" {
  _require_cmd "test-project-init"
  _require_cmd "test-project-scenario-load"
  local init_cmd
  local load_cmd
  init_cmd=$(_cmd_path "test-project-init")
  load_cmd=$(_cmd_path "test-project-scenario-load")

  bash "$init_cmd" --auto-confirm
  run bash "$load_cmd" --scenario smoke-001 --auto-confirm
  assert_success

  local issue_file="$TMP_REPO/worktrees/test-target/.test-target/issues/smoke-001.md"
  [ -f "$issue_file" ]
  grep -q "hello" "$issue_file"
}

# Scenario: observe-once captures stub window
# WHEN observe-once is called with TMUX_STUB_WINDOW set
# THEN output JSON contains window field matching the stub name
@test "smoke: observe-once captures stub window" {
  _require_cmd "observe-once"
  local cmd
  cmd=$(_cmd_path "observe-once")

  mock_tmux_window "ap-#stub" "some captured output"

  run bash "$cmd" --window "ap-#stub"
  assert_success
  echo "$output" | jq -e '.window == "ap-#stub"' > /dev/null
}

# Scenario: problem-detect catches MergeGateError pattern
# WHEN an observation JSON with "MergeGateError: base drift" is passed
# THEN at least 1 detection is returned with category == "merge-gate-failure"
@test "smoke: problem-detect catches MergeGateError pattern" {
  _require_cmd "problem-detect"
  local cmd
  cmd=$(_cmd_path "problem-detect")

  local input_file="$SANDBOX/observe.json"
  echo '{"capture":"... MergeGateError: base drift ...","window":"ap-#stub"}' > "$input_file"

  run bash "$cmd" --input "$input_file"
  assert_success
  echo "$output" | jq -e '.detections | length >= 1' > /dev/null
  echo "$output" | jq -e '.detections[0].category == "merge-gate-failure"' > /dev/null
}

# Scenario: workflow-observe-loop runs 2 cycles with stub
# WHEN workflow-observe-loop is run with MAX_CYCLES=2 and INTERVAL=1
# THEN .observation/last/aggregated.json is generated with cycles_executed == 2
@test "smoke: workflow-observe-loop runs 2 cycles with stub" {
  _require_cmd "workflow-observe-loop" 2>/dev/null || {
    # workflow-observe-loop may be a skill, not a command script
    local skill_path="$REPO_ROOT/skills/workflow-observe-loop/run.sh"
    [[ -f "$skill_path" ]] || skip "workflow-observe-loop not yet implemented (depends on 子 5 #177)"
  }

  mock_tmux_window "ap-#stub" "normal output, no errors"

  run bash -c "
    MAX_CYCLES=2 INTERVAL=1 \
    bash '$REPO_ROOT/skills/workflow-observe-loop/run.sh' \
      --observed-window ap-#stub --auto-stop
  "
  assert_success

  local agg_file="$TMP_REPO/.observation/last/aggregated.json"
  [ -f "$agg_file" ]
  jq -e '.cycles_executed == 2' "$agg_file" > /dev/null
}

# Scenario: issue-draft-from-observation generates markdown
# WHEN detection JSON with merge-gate-failure severity critical is passed
# THEN draft_markdown contains "[Observation]" and recommended_labels contains "from-observation"
@test "smoke: issue-draft-from-observation generates markdown" {
  _require_cmd "issue-draft-from-observation"
  local cmd
  cmd=$(_cmd_path "issue-draft-from-observation")

  local input_file="$SANDBOX/detect.json"
  echo '{"detections":[{"category":"merge-gate-failure","severity":"critical","line":"...","line_number":17}]}' > "$input_file"

  run bash "$cmd" --input "$input_file"
  assert_success
  echo "$output" | jq -e '.draft_markdown | contains("[Observation]")' > /dev/null
  echo "$output" | jq -e '.recommended_labels | contains(["from-observation"])' > /dev/null
}

# Scenario: full chain - init → scenario-load → observe → detect → draft
# WHEN the full co-self-improve pipeline is run end-to-end with stubs
# THEN each step succeeds and the final draft has at least 1 detection
@test "smoke: full chain - init → scenario-load → observe → detect → draft" {
  _require_cmd "test-project-init"
  _require_cmd "test-project-scenario-load"
  local skill_path="$REPO_ROOT/skills/workflow-observe-loop/run.sh"
  [[ -f "$skill_path" ]] || skip "workflow-observe-loop not yet implemented (depends on 子 5 #177)"
  _require_cmd "issue-draft-from-observation"

  local init_cmd load_cmd draft_cmd
  init_cmd=$(_cmd_path "test-project-init")
  load_cmd=$(_cmd_path "test-project-scenario-load")
  draft_cmd=$(_cmd_path "issue-draft-from-observation")

  # Step 1: init
  bash "$init_cmd" --auto-confirm

  # Step 2: load scenario
  bash "$load_cmd" --scenario smoke-001 --auto-confirm

  # Step 3: observe (mock tmux with stub error output)
  mock_tmux_window "ap-#stub" "Error: stub error message"

  MAX_CYCLES=1 INTERVAL=1 \
  bash "$skill_path" --observed-window "ap-#stub" --max-cycles 1

  # Step 4: verify aggregated.json exists with at least 1 detection
  local agg_file="$TMP_REPO/.observation/last/aggregated.json"
  [ -f "$agg_file" ]
  jq -e '.detections_total >= 1' "$agg_file" > /dev/null

  # Step 5: generate issue draft
  run bash "$draft_cmd" --input "$agg_file"
  assert_success
  echo "$output" | jq -e '.draft_markdown | length > 0' > /dev/null
}
