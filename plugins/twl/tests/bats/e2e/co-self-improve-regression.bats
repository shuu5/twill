#!/usr/bin/env bats
# co-self-improve-regression.bats
# E2E regression tests for co-self-improve framework (子 8 / Issue #180)
#
# Regression scenarios:
#   1. scenario-load regression-001 creates 3 issues
#   2. observer-evaluator specialist is invoked on severity >= medium
#   3. observer-evaluator-parser clamps confidence > 75 to 75
#   4. observer-evaluator-parser moves no-quote evaluations to warnings
#   5. pass conditions satisfied for regression-001 baseline
#
# Depends on child issues being merged:
#   子 3 (#175): test-project-{init,reset,scenario-load}
#   子 5 (#177): observe-and-detect composite
#   子 6 (#178): observer-evaluator specialist + parser script
#   子 7 (#179): load-test-baselines reference (regression-001 pass conditions)
#
# Run: bats plugins/twl/tests/bats/e2e/co-self-improve-regression.bats
# Expected execution time: under 10 minutes
#
# BATS_TEST_TIMEOUT: use --timeout 600 when running.

load '../helpers/common'
load '../helpers/git-fixture'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Resolve path to a co-self-improve command script
_cmd_path() {
  local name="$1"
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

# _require_parser: skip if observer-evaluator-parser.sh is not yet implemented
_require_parser() {
  local parser_path="$REPO_ROOT/scripts/observer-evaluator-parser.sh"
  if [[ ! -f "$parser_path" ]]; then
    skip "observer-evaluator-parser.sh not yet implemented (depends on 子 6 #178)"
  fi
  echo "$parser_path"
}

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  TMP_REPO=$(init_temp_repo)
  export TMP_REPO

  PLUGIN_DIR="$REPO_ROOT"
  export PLUGIN_DIR
}

teardown() {
  cleanup_temp_repo "$TMP_REPO"
  common_teardown
}

# ---------------------------------------------------------------------------
# Regression tests (5 cases)
# ---------------------------------------------------------------------------

# Scenario: scenario-load regression-001 creates 3 issues
# WHEN test-project-scenario-load --scenario regression-001 is executed
# THEN exactly 3 issue files exist under worktrees/test-target/.test-target/issues/
@test "regression: scenario-load regression-001 creates 3 issues" {
  _require_cmd "test-project-init"
  _require_cmd "test-project-scenario-load"
  local init_cmd load_cmd
  init_cmd=$(_cmd_path "test-project-init")
  load_cmd=$(_cmd_path "test-project-scenario-load")

  bash "$init_cmd" --mode local --auto-confirm
  run bash "$load_cmd" --scenario regression-001 --auto-confirm
  assert_success

  local issues_dir="$TMP_REPO/worktrees/test-target/.test-target/issues"
  local count
  count=$(ls "$issues_dir" | wc -l)
  [ "$count" -eq 3 ]
}

# Scenario: observer-evaluator specialist invoked on severity >= medium
# WHEN observe-and-detect is called with a stub detection of severity "high"
# AND --evaluator-on flag is set
# THEN the agent call log records an "observer-evaluator" invocation
@test "regression: observer-evaluator specialist invoked on severity>=medium" {
  local observe_cmd
  observe_cmd=$(_cmd_path "observe-and-detect" 2>/dev/null || echo "")
  [[ -n "$observe_cmd" ]] || skip "observe-and-detect not yet implemented (depends on 子 5 #177)"

  local agent_log="$SANDBOX/agent-calls.log"
  mock_agent_call "$agent_log"
  mock_tmux_window "ap-#stub" "some error output"

  run bash "$observe_cmd" \
    --window "ap-#stub" \
    --evaluator-on \
    --stub-detection-severity high
  assert_success

  [ -s "$agent_log" ]
  grep -q "observer-evaluator" "$agent_log"
}

# Scenario: parser clamps confidence > 75
# WHEN observer-evaluator-parser.sh receives a JSON with confidence: 90
# THEN the parsed output has confidence == 75
@test "regression: parser clamps confidence > 75" {
  local parser_path
  parser_path=$(_require_parser)

  local input_file="$SANDBOX/over-confidence.json"
  echo '{"specialist":"observer-evaluator","llm_evaluations":[{"type":"new-finding","quote":"example quote","confidence":90}],"summary":"x"}' > "$input_file"

  run bash "$parser_path" "$input_file"
  assert_success
  echo "$output" | jq -e '.llm_evaluations[0].confidence == 75' > /dev/null
}

# Scenario: parser moves no-quote evaluations to warnings
# WHEN observer-evaluator-parser.sh receives a JSON with an evaluation missing "quote" field
# THEN the evaluation is moved to warnings array and llm_evaluations is empty
@test "regression: parser moves no-quote evaluations to warnings" {
  local parser_path
  parser_path=$(_require_parser)

  local input_file="$SANDBOX/no-quote.json"
  echo '{"specialist":"observer-evaluator","llm_evaluations":[{"type":"new-finding","confidence":60}],"summary":"x"}' > "$input_file"

  run bash "$parser_path" "$input_file"
  assert_success
  echo "$output" | jq -e '.warnings | length == 1' > /dev/null
  echo "$output" | jq -e '.llm_evaluations | length == 0' > /dev/null
}

# Scenario: pass conditions satisfied for regression-001 baseline
# WHEN regression-001 is fully executed (init → load → observe 3 cycles → evaluate)
# THEN all pass conditions from load-test-baselines.md are met:
#   - 3 issues defined
#   - observer detected >= 3 items (stub)
#   - evaluator invoked at least once
@test "regression: pass conditions satisfied for regression-001 baseline" {
  local baselines_file="$REPO_ROOT/refs/load-test-baselines.md"
  [[ -f "$baselines_file" ]] || skip "load-test-baselines.md not yet implemented (depends on 子 7 #179)"

  _require_cmd "test-project-init"
  _require_cmd "test-project-scenario-load"
  local skill_path="$REPO_ROOT/skills/workflow-observe-loop/run.sh"
  [[ -f "$skill_path" ]] || skip "workflow-observe-loop not yet implemented (depends on 子 5 #177)"

  local init_cmd load_cmd
  init_cmd=$(_cmd_path "test-project-init")
  load_cmd=$(_cmd_path "test-project-scenario-load")

  local agent_log="$SANDBOX/agent-calls-regression.log"
  mock_agent_call "$agent_log"

  # Set up agent stub to record observer-evaluator calls
  cat >> "$STUB_BIN/cld" <<'EXTRASTUB'
# also check for observer-evaluator pattern
if echo "$*" | grep -q "observer-evaluator"; then
  echo "$(date -u +%FT%TZ) observer-evaluator $*" >> "${AGENT_CALL_LOG}"
fi
EXTRASTUB

  # Step 1: init + load regression-001 (3 issues)
  bash "$init_cmd" --mode local --auto-confirm
  bash "$load_cmd" --scenario regression-001 --auto-confirm

  local issues_dir="$TMP_REPO/worktrees/test-target/.test-target/issues"
  local issue_count
  issue_count=$(ls "$issues_dir" | wc -l)

  # Pass condition 1: 3 issues defined
  [ "$issue_count" -eq 3 ]

  # Step 2: observe with stub detecting >= 3 items
  mock_tmux_window "ap-#stub" "Error: issue-1 Error: issue-2 Error: issue-3"

  MAX_CYCLES=3 INTERVAL=1 \
  bash "$skill_path" --observed-window "ap-#stub" --max-cycles 3

  local agg_file="$TMP_REPO/.observation/last/aggregated.json"
  [ -f "$agg_file" ]

  # Pass condition 2: observer detected >= 3 items
  jq -e '.detections_total >= 3' "$agg_file" > /dev/null

  # Pass condition 3: evaluator invoked at least once
  [ -s "$agent_log" ]
  grep -q "observer-evaluator" "$agent_log"
}
