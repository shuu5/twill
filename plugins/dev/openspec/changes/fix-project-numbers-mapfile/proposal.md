## Why

`PROJECT_NUMBERS` / `project_numbers` 変数が unquoted word-split に依存しており、bash best practice に反する。現在は整数値のみのため実害はないが、将来的な誤動作リスクと `shellcheck` の WARNING を排除するために修正が必要。

## What Changes

- `scripts/project-board-archive.sh`（line 68）: `for PROJECT_NUM in $PROJECT_NUMBERS` → `mapfile` パターンへ置換
- `scripts/project-board-backfill.sh`（line 74）: 同上
- `scripts/chain-runner.sh`（line 209, 344）: `for PROJECT_NUM in $project_numbers` × 2箇所 → `mapfile` パターンへ置換
- `scripts/autopilot-plan-board.sh`（line 39）: 同上（数値バリデーションガードを維持）

## Capabilities

### New Capabilities

なし（純粋なコード品質改善）

### Modified Capabilities

- `PROJECT_NUMBERS` の取得・イテレーションが `mapfile -t` + `"${PROJECT_NUMS[@]}"` パターンに統一される

## Impact

- **影響スクリプト**: `project-board-archive.sh`, `project-board-backfill.sh`, `chain-runner.sh`, `autopilot-plan-board.sh`（計4ファイル5箇所）
- **依存関係**: bash 4.0+ 必須（`mapfile` builtin 使用。全スクリプトは `#!/usr/bin/env bash` で Linux 環境のみのため問題なし）
- **外部 API**: 変更なし
- **既存動作**: 機能変更なし（整数値プロジェクト番号のイテレーション結果は同一）
