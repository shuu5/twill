## Why

co-self-improve framework の test-scenario-catalog.md には smoke と regression-001/002 しかなく、autopilot の full-chain 遷移（setup → test-ready → pr-verify → pr-merge）を通すシナリオと、既知 Bug (#436/#438/#439) を再現するシナリオが存在しない。これらの欠如により、Bug 再現検証と chain 遷移の regression テストが不可能な状態である。

## What Changes

- `plugins/twl/refs/test-scenario-catalog.md` に 4 つの新規シナリオを追加:
  - `regression-003`: full-chain regression（medium complexity Issue で chain 全遷移を通す）
  - `regression-004`: Bug #436 再現（DeltaSpec を使う Issue で `issue:` フィールド欠落を誘発）
  - `regression-005`: Bug #438 再現（長時間実行 Issue で Orchestrator polling timeout を誘発）
  - `regression-006`: Bug #439 再現（merge-gate 到達時に `phase-review.json` 不在を誘発）

## Capabilities

### New Capabilities

- **regression-003**: full-chain 遷移（setup→test-ready→pr-verify→pr-merge）を通す regression シナリオ
- **regression-004**: Bug #436 (`twl spec new` が `.deltaspec.yaml` に `issue:` フィールドを生成しない) の再現シナリオ
- **regression-005**: Bug #438 (orchestrator polling loop が Bash timeout 120秒で停止) の再現シナリオ
- **regression-006**: Bug #439 (merge-gate が `phase-review.json` の存在を検査しない) の再現シナリオ

### Modified Capabilities

なし

## Impact

- **変更ファイル**: `plugins/twl/refs/test-scenario-catalog.md`（追記のみ、既存シナリオ変更なし）
- **影響 API/依存**: なし
- **テスト**: 本 PR 自体がテストシナリオ定義の追加であり、co-self-improve framework で利用される
