#!/usr/bin/env bats
# workflow-pr-verify.bats - Issue #144 / Phase 4-A Layer 2
#
# workflow-pr-verify の chain step 順序を回帰テストとして凍結する。
# 重要: ac-verify は Issue #134 で step 3.5 (pr-test の後) に確定済み。
#       ts-preflight → phase-review → scope-judge → pr-test → ac-verify

load '../helpers/workflow-scenario-env'
load '../helpers/trace-assertions'

setup() {
  setup_workflow_scenario_env
}

teardown() {
  teardown_workflow_scenario_env
}

@test "workflow-pr-verify: ts-preflight → phase-review → scope-judge → pr-test → ac-verify の順で実行" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-verify/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order \
    ts-preflight \
    phase-review \
    scope-judge \
    pr-test \
    ac-verify
  [ "$status" -eq 0 ]
}

@test "workflow-pr-verify: ac-verify が必ず trace に現れる（Issue #134 回帰テスト）" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-verify/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_contains ac-verify
  [ "$status" -eq 0 ]
}

@test "workflow-pr-verify: ac-verify は pr-test より後に実行される（順序の不変条件）" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-verify/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order pr-test ac-verify
  [ "$status" -eq 0 ]
}

@test "workflow-pr-verify: 30 秒以内に完了する" {
  local start_ts end_ts
  start_ts=$(date +%s)
  bash "$PLUGIN_ROOT/skills/workflow-pr-verify/dry-run.sh" >/dev/null 2>&1
  end_ts=$(date +%s)
  [ $((end_ts - start_ts)) -lt 30 ]
}
