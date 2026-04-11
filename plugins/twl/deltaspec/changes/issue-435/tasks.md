## 1. find_deltaspec_root() 改善（cli/twl）

- [x] 1.1 `cli/twl/src/twl/spec/paths.py` の `find_deltaspec_root()` を config.yaml マーカーベースの walk-up に変更
- [x] 1.2 walk-up で見つからない場合の walk-down fallback（git toplevel から maxdepth=3）を追加
- [x] 1.3 複数ヒット時に cwd に最も近いものを選択するロジックを追加
- [x] 1.4 `DeltaspecNotFoundError` を raise（0件時）
- [x] 1.5 `twl spec new` で `deltaspec/` 新規作成時に `config.yaml` を自動生成するロジック追加（`cli/twl/src/twl/spec/new.py`）
- [x] 1.6 `pytest tests/` で既存 spec テストが全てパスすることを確認（pre-existing 24件除く）

## 2. chain-runner.sh deltaspec 判定変更（plugins/twl）

- [x] 2.1 `plugins/twl/scripts/chain-runner.sh` の deltaspec 判定を config.yaml ベースチェックに変更
- [x] 2.2 walk-down fallback（`find -maxdepth 5`）と `resolve_deltaspec_root()` ヘルパー追加
- [x] 2.3 変更後のローカル動作確認（worktree root から `bash chain-runner.sh init 435` → `deltaspec:true` 確認）

## 3. root deltaspec/changes/ 統合（31件）

- [x] 3.1 root `deltaspec/archive/` 34件を `plugins/twl/deltaspec/changes/` にコピー → `twl spec archive --skip-specs` で archive
- [x] 3.2 コンフリクトなし（--skip-specs で specs 統合なし・issue-435 での specs 統合自動化が今後対応）
- [x] 3.3 全 34 changes が `plugins/twl/deltaspec/changes/archive/` に移動済み（36件中 34件が今回追加）
- [x] 3.4 root `deltaspec/` ディレクトリを削除済み

## 4. chain spec-archive ステップ追加（plugins/twl）

- [x] 4.1 `plugins/twl/scripts/auto-merge.sh` の spec archive を `--skip-specs` なしに変更
- [x] 4.2 specs 統合失敗時の WARNING ログ + `--skip-specs` フォールバック追加
- [x] 4.3 `plugins/twl/scripts/autopilot-orchestrator.sh` の `_archive_deltaspec_changes_for_issue()` から `--skip-specs` 除去
- [x] 4.4 specs 統合失敗時の `--skip-specs` フォールバック + WARNING ログ追加。deltaspec_root walk-down 対応も追加

## 5. Architecture Context 更新

- [x] 5.1 `cli/twl/architecture/domain/contexts/spec-management.md` の Constraints に「config.yaml を持つ deltaspec/ のみ有効」を追記
