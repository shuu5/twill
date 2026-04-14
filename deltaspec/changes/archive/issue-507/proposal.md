## Why

autopilot の state file (`.autopilot/issues/issue-{N}.json`) には進捗を表す3フィールド (`status` / `current_step` / `workflow_done`) が存在するが、SSOT が不明確なため、外部観察者 (Monitor / su-observer) が「どのフィールドを信頼すればよいか」を判断できず、Wave 7 で誤警告が繰り返し発生した。

## What Changes

- `status` を SSOT（Single Source of Truth）に指定し、`current_step` と `workflow_done` を derived/廃止に格下げする（Option 1 採用）
- `workflow_done` を廃止し、`inject_next_workflow` トリガーを `status` の terminal 値検知に切り替える
- `plugins/twl/architecture/domain/contexts/autopilot.md` の IssueState 表を `conflict` を含む完全な状態遷移グラフに更新し、SSOT フィールドを明記する
- `plugins/twl/architecture/decisions/ADR-016-state-schema-ssot.md` を新規作成し、Option 1 採用の決定根拠を記録する
- `workflow_done` の writer/reader を全箇所削除または代替ロジックに置換する

## Capabilities

### New Capabilities

- Monitor / su-observer が `jq -r '.status' issue-N.json` 単一クエリで進捗判定できる
- `autopilot.md` に完全な状態遷移グラフ（`conflict` を含む）が明記される

### Modified Capabilities

- `inject_next_workflow` のトリガー機構: `workflow_done` フィールドポーリング → `status` の terminal 値（`merge-ready`）検知に変更
- `state.py` `_PILOT_ISSUE_ALLOWED_KEYS`: `workflow_done` エントリを削除
- `resolve_next_workflow.py`: `workflow_done` 参照を `status` 参照に変更
- `autopilot-orchestrator.sh`: `workflow_done` の read/write/clear を `status` ベースに変更
- `chain-runner.sh`: 各 workflow-* SKILL の `workflow_done=<name>` write を削除
- `pre-compact-checkpoint.sh`: `workflow_done` 参照を削除

## Impact

- `cli/twl/src/twl/autopilot/state.py`（`_PILOT_ISSUE_ALLOWED_KEYS` から `workflow_done` 削除）
- `cli/twl/src/twl/autopilot/resolve_next_workflow.py`（reader ロジック変更）
- `plugins/twl/scripts/autopilot-orchestrator.sh`（inject トリガー機構変更、L503/594/742-750/819/867）
- `plugins/twl/scripts/chain-runner.sh`（workflow_done write 箇所の削除）
- `plugins/twl/scripts/hooks/pre-compact-checkpoint.sh`（参照削除）
- `plugins/twl/architecture/domain/contexts/autopilot.md`（IssueState 表更新、SSOT 明記）
- `plugins/twl/architecture/decisions/ADR-016-state-schema-ssot.md`（新規）
- `plugins/twl/architecture/decisions/ADR-003-unified-state-file.md`（参照リンク追加）
- `plugins/twl/skills/workflow-{setup,test-ready,pr-verify,pr-fix,pr-merge}/SKILL.md`（5 ファイル）
- `plugins/twl/tests/unit/inject-next-workflow/*.bats`（3 ファイル）
- `plugins/twl/tests/scenarios/co-autopilot-smoke.test.sh`
