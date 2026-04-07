#!/usr/bin/env bats
# workflow-pr-merge.bats - Issue #144 / Phase 4-A Layer 2
#
# workflow-pr-merge の chain step 順序を回帰テストとして凍結する。
#   e2e-screening → pr-cycle-report → pr-cycle-analysis → all-pass-check →
#   merge-gate → auto-merge
#
# NOTE: change-archive は SKILL.md chain ライフサイクル表に未含まれるため
#       本 Issue 時点ではテスト対象外（Phase 2 トリアージ後に追加予定）。

load '../helpers/workflow-scenario-env'
load '../helpers/trace-assertions'

setup() {
  setup_workflow_scenario_env
}

teardown() {
  teardown_workflow_scenario_env
}

@test "workflow-pr-merge: e2e-screening → pr-cycle-report → pr-cycle-analysis → all-pass-check → merge-gate → auto-merge の順で実行" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-merge/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order \
    e2e-screening \
    pr-cycle-report \
    pr-cycle-analysis \
    all-pass-check \
    merge-gate \
    auto-merge
  [ "$status" -eq 0 ]
}

@test "workflow-pr-merge: auto-merge は merge-gate より後に実行される（不変条件 C）" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-merge/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order merge-gate auto-merge
  [ "$status" -eq 0 ]
}

@test "workflow-pr-merge: 全 6 step が trace に存在する" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-merge/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_contains \
    e2e-screening \
    pr-cycle-report \
    pr-cycle-analysis \
    all-pass-check \
    merge-gate \
    auto-merge
  [ "$status" -eq 0 ]
}

@test "workflow-pr-merge: 30 秒以内に完了する" {
  local start_ts end_ts
  start_ts=$(date +%s)
  bash "$PLUGIN_ROOT/skills/workflow-pr-merge/dry-run.sh" >/dev/null 2>&1
  end_ts=$(date +%s)
  [ $((end_ts - start_ts)) -lt 30 ]
}
