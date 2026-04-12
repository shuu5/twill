## Why

`autopilot-orchestrator.sh` の `_archive_deltaspec_changes_for_issue()` 関数が `chain-runner.sh` の `resolve_deltaspec_root()` と同一の walk-down find ロジックをインラインで重複実装している。将来 `resolve_deltaspec_root` のロジックが変更された場合（exclude リスト・maxdepth 等）、`autopilot-orchestrator.sh` が追従しない可能性がある DRY 違反を解消する。

## What Changes

- `plugins/twl/scripts/lib/deltaspec-helpers.sh` を新設し、`resolve_deltaspec_root()` 関数をそこに移動する
- `chain-runner.sh` から `resolve_deltaspec_root()` の定義を削除し、`deltaspec-helpers.sh` を source するよう変更する
- `autopilot-orchestrator.sh` の `_archive_deltaspec_changes_for_issue()` からインライン walk-down find ロジックを削除し、`resolve_deltaspec_root()` 呼び出しに置換する。`deltaspec-helpers.sh` を source する
- bats テストを追加して DRY 解消後も既存の挙動が維持されることを確認する

## Capabilities

### New Capabilities

- `plugins/twl/scripts/lib/deltaspec-helpers.sh`: `resolve_deltaspec_root()` の共有ライブラリ。両スクリプトから source 可能

### Modified Capabilities

- `chain-runner.sh`: `resolve_deltaspec_root()` 定義を `deltaspec-helpers.sh` に委譲
- `autopilot-orchestrator.sh`: `_archive_deltaspec_changes_for_issue()` 内の重複 find ロジックを `resolve_deltaspec_root()` 呼び出しに置換

## Impact

- 影響ファイル: `plugins/twl/scripts/chain-runner.sh`, `plugins/twl/scripts/autopilot-orchestrator.sh`, `plugins/twl/scripts/lib/deltaspec-helpers.sh`（新規）
- API 変更なし（`resolve_deltaspec_root` の挙動は同一）
- テスト: `test/bats/` に回帰テスト追加
- shellcheck: 両スクリプトで lint パス必須
