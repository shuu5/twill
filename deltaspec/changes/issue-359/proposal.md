## Why

supervisor-redesign フェーズ（Phase 6）において、旧 Observer ロールが Supervisor に改名された。しかし `intervention-catalog.md` と `intervene-*.md` コマンド群に旧称 "Observer" がメタ認知文脈で残存しており、ロール名の不一致が発生している。

## What Changes

- `plugins/twl/refs/intervention-catalog.md`: 介入判断主体としての "Observer" を "Supervisor" に置換（Live Observation コンテキストの Observer は対象外）
- `plugins/twl/commands/intervene-auto.md`: description 行の "Observer" を "Supervisor" に置換
- `plugins/twl/commands/intervene-confirm.md`: description 行および本文の "Observer" を "Supervisor" に置換
- `plugins/twl/commands/intervene-escalate.md`: description 行および本文の "Observer" を "Supervisor" に置換

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- **intervention-catalog**: 介入判断主体の呼称が Observer → Supervisor に統一される
- **intervene-auto / intervene-confirm / intervene-escalate**: 各コマンドの description と本文が Supervisor ロール名と一致する

## Impact

- `plugins/twl/refs/intervention-catalog.md`
- `plugins/twl/commands/intervene-auto.md`
- `plugins/twl/commands/intervene-confirm.md`
- `plugins/twl/commands/intervene-escalate.md`
