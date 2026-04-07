#!/usr/bin/env bats
# workflow-test-ready.bats - Issue #144 / Phase 4-A Layer 2
#
# workflow-test-ready の chain step 順序を回帰テストとして凍結する。
#   change-id-resolve → test-scaffold → check → change-apply → post-change-apply

load '../helpers/workflow-scenario-env'
load '../helpers/trace-assertions'

setup() {
  setup_workflow_scenario_env
}

teardown() {
  teardown_workflow_scenario_env
}

@test "workflow-test-ready: change-id-resolve → test-scaffold → check → change-apply → post-change-apply の順で実行" {
  run bash "$PLUGIN_ROOT/skills/workflow-test-ready/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order \
    change-id-resolve \
    test-scaffold \
    check \
    change-apply \
    post-change-apply
  [ "$status" -eq 0 ]
}

@test "workflow-test-ready: 全 5 step が trace に存在する" {
  run bash "$PLUGIN_ROOT/skills/workflow-test-ready/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_contains \
    change-id-resolve \
    test-scaffold \
    check \
    change-apply \
    post-change-apply
  [ "$status" -eq 0 ]
}

@test "workflow-test-ready: 30 秒以内に完了する" {
  local start_ts end_ts
  start_ts=$(date +%s)
  bash "$PLUGIN_ROOT/skills/workflow-test-ready/dry-run.sh" >/dev/null 2>&1
  end_ts=$(date +%s)
  [ $((end_ts - start_ts)) -lt 30 ]
}
