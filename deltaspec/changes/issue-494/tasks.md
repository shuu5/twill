## 1. chain-runner.sh 修正

- [x] 1.1 `step_all_pass_check()` (L1028) の state write コマンドに `--set "workflow_done=pr-merge"` を追加する

## 2. smoke テスト追加

- [x] 2.1 `test-fixtures/` 配下に `all-pass-check` smoke テストファイルを作成する（→ `plugins/twl/tests/unit/all-pass-check-workflow-done/all-pass-check-workflow-done.bats`）
- [x] 2.2 smoke テストで PASS 時に `workflow_done=pr-merge` が state に書かれることを確認するテストケースを実装する

## 3. 整合確認

- [x] 3.1 `workflow-pr-merge/SKILL.md` L118 付近の `workflow_done=pr-merge` 書き込み指示と値が一致することを確認する（変更不要）
- [x] 3.2 `autopilot-orchestrator.sh` が `workflow_done=pr-merge` を読んで `non_terminal_chain_end` を回避できることを smoke テストで確認する
