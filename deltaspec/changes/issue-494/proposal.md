## Why

`chain-runner.sh` の `step_all_pass_check()` は `status=merge-ready` を書き込む際に `workflow_done=pr-merge` を書かないため、LLM が SKILL.md の指示を見落とすと `autopilot-orchestrator.sh` 側で `non_terminal_chain_end` を誤検知する。script 側を SSOT として `workflow_done` 書き込みを保証する必要がある。

## What Changes

- `plugins/twl/scripts/chain-runner.sh` の `step_all_pass_check()` (L990-1039) で `status=merge-ready` 書き込み時に `--set workflow_done=pr-merge` を追加
- 失敗時 (status=failed) は `workflow_done` を書かず exit 1 を維持（変更なし）
- smoke テストケースを追加し、正常終了後に state に `workflow_done=pr-merge` が書かれることを確認

## Capabilities

### New Capabilities

なし（既存動作の保証強化のみ）

### Modified Capabilities

- `step_all_pass_check()`: `status=merge-ready` 書き込みと同時に `workflow_done=pr-merge` を必ず書くようになる。SKILL.md 側の LLM 指示による書き込みと値が一致するため二重書き込み時も不一致は発生しない

## Impact

- **影響ファイル**: `plugins/twl/scripts/chain-runner.sh`
- **参照**: `workflow-pr-merge/SKILL.md` L118 付近（既存 `workflow_done=pr-merge` 書き込み実績、整合確認のみ）
- **テスト追加**: `test-fixtures/` 配下に smoke テストケース追加
- **スコープ外**: `worker-terminal-guard.sh` は変更しない
