## Why

`scripts/autopilot-plan-board.sh` L89 の正規表現 `^[a-zA-Z0-9_.-]+$` が `..` を許容しており、`plan.yaml` に親ディレクトリパスが記録される理論的なリスクがある。防御的コーディングとして修正する。

## What Changes

- `autopilot-plan-board.sh` L89 の正規表現を `^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$` に変更（先頭の `.` を禁止）
- `..` および `.` を明示的に拒否する条件を追加

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- リポジトリ名バリデーション: `..` および `.` を明示的に拒否

## Impact

- 変更ファイル: `scripts/autopilot-plan-board.sh` のみ
- 実用上の影響なし（GitHub リポジトリ名に `..` は使用不可）
