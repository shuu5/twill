#!/usr/bin/env bats
# workflow-pr-fix.bats - Issue #144 / Phase 4-A Layer 2
#
# workflow-pr-fix の chain step 順序を回帰テストとして凍結する。
#   fix-phase → post-fix-verify → warning-fix

load '../helpers/workflow-scenario-env'
load '../helpers/trace-assertions'

setup() {
  setup_workflow_scenario_env
}

teardown() {
  teardown_workflow_scenario_env
}

@test "workflow-pr-fix: fix-phase → post-fix-verify → warning-fix の順で実行" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-fix/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order \
    fix-phase \
    post-fix-verify \
    warning-fix
  [ "$status" -eq 0 ]
}

@test "workflow-pr-fix: 全 3 step が trace に存在する" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-fix/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_contains fix-phase post-fix-verify warning-fix
  [ "$status" -eq 0 ]
}

@test "workflow-pr-fix: 30 秒以内に完了する" {
  local start_ts end_ts
  start_ts=$(date +%s)
  bash "$PLUGIN_ROOT/skills/workflow-pr-fix/dry-run.sh" >/dev/null 2>&1
  end_ts=$(date +%s)
  [ $((end_ts - start_ts)) -lt 30 ]
}
