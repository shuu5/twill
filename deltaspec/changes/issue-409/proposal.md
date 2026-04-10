## Why

co-autopilot の SKILL.md 変更に対する integration test が不在であり、Pilot の実際の起動フロー（plan.yaml 生成 → session 初期化 → orchestrator 起動）をランタイムで検証する手段がない。ドキュメント検証テストのみでは、ランタイム動作の正しさを保証できない。

## What Changes

- `tests/scenarios/` に co-autopilot Pilot 起動フローの integration test を追加
- smoke test で実際の Pilot 起動コマンドを dry-run または mock モードで実行し、plan.yaml 生成・session 初期化・orchestrator 起動の各ステップを検証する
- 既存の `tests/scenarios/skillmd-pilot-fixes.test.sh`（ドキュメント検証）と明確に区別する

## Capabilities

### New Capabilities

- **co-autopilot-smoke.test.sh**: Pilot 起動フローを dry-run/mock で実行し、以下を検証する:
  - plan.yaml の生成（エラー 0 回）
  - session 初期化の成功
  - orchestrator 起動への到達
- integration test として CI で実行可能

### Modified Capabilities

- なし（既存テストは変更しない）

## Impact

- 追加ファイル: `tests/scenarios/co-autopilot-smoke.test.sh`
- 依存: co-autopilot の Pilot 起動スクリプト（`plugins/twl/scripts/autopilot-*.sh`）
- CI への影響: smoke test を `test:scenarios` スイートに組み込む
