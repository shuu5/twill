## Why

`autopilot-orchestrator.sh` の `inject_next_workflow()` が `pr-merge` を検出した際 inject をスキップして return 0 する分岐が存在し、Worker chain が `warning-fix` terminal で停止している場合（`status=running`）に deadlock する。skip 経路が `RESOLVE_FAIL_COUNT` をリセットするため stagnate 検知も回避され、observer 手動介入なしに Wave が完了できなくなる。

## What Changes

- `autopilot-orchestrator.sh:930-935` の pr-merge skip 分岐を削除（Option A）し、`/twl:workflow-pr-merge` を通常の inject 経路に統合する
- `inject_next_workflow()` に連続 inject timeout 上限カウンタ（`INJECT_TIMEOUT_COUNT`）を追加し、上限到達時に `status=failed` + `failure.reason=inject_exhausted_pr_merge` へ遷移して force-exit する（環境変数 `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX` でオーバーライド、デフォルト 5）
- BATS テスト `plugins/twl/tests/unit/inject-next-workflow/pr-merge-skip-guard.bats` を新規追加し、3 ケース（inject 成功・重複防止・timeout force-exit）を検証する
- `plugins/twl/architecture/domain/contexts/autopilot.md` に pr-merge resolve 時の deadlock 再発防止メモと ADR-018 相互参照を追記する

## Capabilities

### New Capabilities

- `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX` 環境変数による inject timeout 上限の制御
- inject timeout 上限到達時の `status=failed` 遷移と `cleanup_worker` 呼び出し

### Modified Capabilities

- `inject_next_workflow()`: pr-merge skip 分岐を削除し通常 inject 経路に統合
- `inject_next_workflow()`: `INJECT_TIMEOUT_COUNT` カウンタを追加（pr-merge 限定スコープ）

## Impact

- `plugins/twl/scripts/autopilot-orchestrator.sh`（変更：skip 分岐削除 + timeout カウンタ + ログ改善）
- `plugins/twl/tests/unit/inject-next-workflow/pr-merge-skip-guard.bats`（新規：BATS テスト 3 ケース）
- `plugins/twl/architecture/domain/contexts/autopilot.md`（変更：再発防止メモ + ADR-018 相互参照）
