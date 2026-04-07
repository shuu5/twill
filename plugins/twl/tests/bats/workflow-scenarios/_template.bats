#!/usr/bin/env bats
# _template.bats - Issue #144 / Phase 4-A Layer 2
#
# 将来 workflow を追加する際の bats workflow-scenarios テンプレート。
# このファイルは bats から実行されないよう先頭に skip を入れている。
# 新規 workflow テストを書く場合は本ファイルをコピーして workflow 名にリネームし、
# skip を削除して dry-run.sh を実装すること。

load '../helpers/workflow-scenario-env'
load '../helpers/trace-assertions'
load '../helpers/mock-specialists'

setup() {
  setup_workflow_scenario_env
}

teardown() {
  teardown_workflow_scenario_env
}

@test "TEMPLATE: workflow-<name> dry-run order regression test" {
  skip "template only"

  # 1. dry-run.sh を実行（trace.jsonl が export 済み）
  run bash "$PLUGIN_ROOT/skills/workflow-<name>/dry-run.sh"
  [ "$status" -eq 0 ]

  # 2. trace の順序を assert
  run assert_trace_order step1 step2 step3
  [ "$status" -eq 0 ]
}
