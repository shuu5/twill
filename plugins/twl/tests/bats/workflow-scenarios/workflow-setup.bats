#!/usr/bin/env bats
# workflow-setup.bats - Issue #144 / Phase 4-A Layer 2
#
# workflow-setup の chain step 順序を回帰テストとして凍結する。
# - 通常 path: init → board-status-update → crg-auto-build → arch-ref →
#              change-propose → ac-extract
# - quick path: init → board-status-update → ac-extract → ac-verify
#   （quick の場合 SKILL.md は workflow-test-ready をスキップし
#   ac-verify まで実行して停止。merge-gate は workflow-pr-merge が担当。
#   ADR-018 準拠、#671 修正）
#
# trace は dry-run.sh が TWL_CHAIN_TRACE に書き出す JSON Lines。

load '../helpers/workflow-scenario-env'
load '../helpers/trace-assertions'

setup() {
  setup_workflow_scenario_env
}

teardown() {
  teardown_workflow_scenario_env
}

@test "workflow-setup: 通常 path で init → board-status-update → crg-auto-build → arch-ref → change-propose → ac-extract の順で実行" {
  run bash "$PLUGIN_ROOT/skills/workflow-setup/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order \
    init \
    worktree-create \
    board-status-update \
    crg-auto-build \
    arch-ref \
    change-propose \
    ac-extract
  [ "$status" -eq 0 ]
}

@test "workflow-setup: 通常 path では ac-verify を呼ばない（次 workflow へ遷移）" {
  run bash "$PLUGIN_ROOT/skills/workflow-setup/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_not_contains ac-verify merge-gate
  [ "$status" -eq 0 ]
}

@test "workflow-setup: quick path で ac-verify まで実行し停止（#671: merge-gate は workflow-pr-merge が担当）" {
  run bash "$PLUGIN_ROOT/skills/workflow-setup/dry-run.sh" --quick
  [ "$status" -eq 0 ]

  # 全 step（init を含む setup 系）→ ac-verify で停止。merge-gate は含まない
  run assert_trace_order \
    init \
    board-status-update \
    ac-extract \
    ac-verify
  [ "$status" -eq 0 ]

  # merge-gate が trace に含まれないことを検証（ADR-018 準拠）
  run assert_trace_not_contains merge-gate
  [ "$status" -eq 0 ]
}

@test "workflow-setup: quick path でも ac-verify が trace に必ず現れる（regression freeze）" {
  run bash "$PLUGIN_ROOT/skills/workflow-setup/dry-run.sh" --quick
  [ "$status" -eq 0 ]

  run assert_trace_contains ac-verify
  [ "$status" -eq 0 ]
}

@test "workflow-setup: 30 秒以内に完了する" {
  local start_ts end_ts
  start_ts=$(date +%s)
  bash "$PLUGIN_ROOT/skills/workflow-setup/dry-run.sh" >/dev/null 2>&1
  end_ts=$(date +%s)
  [ $((end_ts - start_ts)) -lt 30 ]
}
