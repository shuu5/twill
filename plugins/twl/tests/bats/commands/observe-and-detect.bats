#!/usr/bin/env bats
# observe-and-detect.bats - structural validation of observe-and-detect composite

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Case 1: composite 順次実行 (observe-once → problem-detect が呼ばれ統合 JSON が出る)
# ---------------------------------------------------------------------------

@test "observe-and-detect: file exists with composite type" {
  local cmd_md="$REPO_ROOT/commands/observe-and-detect.md"
  [ -f "$cmd_md" ]
  grep -q 'type: composite' "$cmd_md"
  grep -q 'effort: medium' "$cmd_md"
}

@test "observe-and-detect: calls observe-once then problem-detect in order" {
  local cmd_md="$REPO_ROOT/commands/observe-and-detect.md"
  local observe_line problem_line
  observe_line=$(grep -n 'observe-once' "$cmd_md" | head -1 | cut -d: -f1)
  problem_line=$(grep -n 'problem-detect' "$cmd_md" | head -1 | cut -d: -f1)
  [ "$observe_line" -lt "$problem_line" ]
}

# ---------------------------------------------------------------------------
# Case 2: evaluator off (--evaluator-on 無しで specialist が呼ばれない)
# ---------------------------------------------------------------------------

@test "observe-and-detect: evaluator is optional via --evaluator-on flag" {
  local cmd_md="$REPO_ROOT/commands/observe-and-detect.md"
  grep -q '\-\-evaluator-on' "$cmd_md"
  grep -q 'evaluator_output.*null' "$cmd_md"
}

# ---------------------------------------------------------------------------
# Case 3: evaluator on + severity condition
# ---------------------------------------------------------------------------

@test "observe-and-detect: evaluator triggers on severity critical or warning" {
  local cmd_md="$REPO_ROOT/commands/observe-and-detect.md"
  grep -q 'severity' "$cmd_md"
  grep -q 'observer-evaluator' "$cmd_md"
}

# ---------------------------------------------------------------------------
# Context budget: 100 行以内
# ---------------------------------------------------------------------------

@test "observe-and-detect: file is within 100 lines" {
  local cmd_md="$REPO_ROOT/commands/observe-and-detect.md"
  local lines
  lines=$(wc -l < "$cmd_md")
  [ "$lines" -le 100 ]
}
