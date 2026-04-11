## Why

`find_deltaspec_root()` がディレクトリ名のみで検索するため、worktree root の `deltaspec/`（config.yaml なし）が `plugins/twl/deltaspec/`（config.yaml あり）より先に検出される。これにより Wave 18-24 の autopilot セッションで root に 31 件の未統合 changes が蓄積され、正規の DeltaSpec ワークフローが機能しない状態になっている。

## What Changes

- `find_deltaspec_root()` を config.yaml マーカーベースのハイブリッド検出方式に変更（walk-up + walk-down fallback）
- `chain-runner.sh` の deltaspec 判定を `config.yaml` 存在チェックに変更
- root `deltaspec/changes/` の 31 changes を `plugins/twl/deltaspec/changes/archive/` へ機械的統合
- root `deltaspec/` ディレクトリを削除
- `auto-merge.sh` に PR merge 後の `twl spec archive` 自動実行を追加
- `autopilot-orchestrator.sh` から `--skip-specs` を除去し specs 統合を有効化

## Capabilities

### New Capabilities

- `find_deltaspec_root()`: config.yaml のない deltaspec/ をスキップし、適切なコンポーネントの DeltaSpec を自動検出
- `twl spec new`: deltaspec/ 新規作成時に config.yaml を自動生成
- chain spec-archive: PR merge 後に change を archive し specs に自動統合

### Modified Capabilities

- `find_deltaspec_root()`: walk-up のみ → walk-up + walk-down ハイブリッド（config.yaml マーカー必須）
- `chain-runner.sh` init: `deltaspec/` ディレクトリ存在チェック → `deltaspec/config.yaml` 存在チェック
- `autopilot-orchestrator.sh` `archive_done_issues()`: `--skip-specs` → specs 統合付き archive（失敗時フォールバック）

## Impact

- `cli/twl/src/twl/spec/paths.py`: `find_deltaspec_root()` 実装変更
- `cli/twl/src/twl/spec/new.py` または `cli/twl/src/twl/spec/`: `config.yaml` 自動生成ロジック追加
- `cli/twl/architecture/domain/contexts/spec-management.md`: Constraints 更新
- `plugins/twl/scripts/chain-runner.sh`: deltaspec 判定ロジック変更
- `plugins/twl/scripts/auto-merge.sh`: spec-archive ステップ追加
- `plugins/twl/scripts/autopilot-orchestrator.sh`: `--skip-specs` 除去
- `plugins/twl/deltaspec/changes/archive/`: 31 changes 追加
- `plugins/twl/deltaspec/specs/`: 31 changes の spec 統合（変更あり）
- root `deltaspec/`: 削除
