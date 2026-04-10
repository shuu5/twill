## 1. find_deltaspec_root() 改善（cli/twl）

- [ ] 1.1 `cli/twl/src/twl/spec/paths.py` の `find_deltaspec_root()` を config.yaml マーカーベースの walk-up に変更
- [ ] 1.2 walk-up で見つからない場合の walk-down fallback（git toplevel から maxdepth=3）を追加
- [ ] 1.3 複数ヒット時に cwd に最も近いものを選択するロジックを追加
- [ ] 1.4 `DeltaspecNotFoundError` を raise（0件時）
- [ ] 1.5 `twl spec new` で `deltaspec/` 新規作成時に `config.yaml` を自動生成するロジック追加（`cli/twl/src/twl/spec/new.py`）
- [ ] 1.6 `pytest tests/` で既存 spec テストが全てパスすることを確認

## 2. chain-runner.sh deltaspec 判定変更（plugins/twl）

- [ ] 2.1 `plugins/twl/scripts/chain-runner.sh` L277 の `[[ -d "$root/deltaspec" ]]` を config.yaml ベースチェックに変更
- [ ] 2.2 walk-down fallback（`find "$root" -maxdepth 3 -name config.yaml -path '*/deltaspec/*'`）を追加
- [ ] 2.3 変更後のローカル動作確認（worktree root から `bash chain-runner.sh init 435` 等）

## 3. root deltaspec/changes/ 統合（31件）

- [ ] 3.1 `plugins/twl/` から `twl spec archive issue-{323..410}` を Issue 番号順に実行（機械的統合）
- [ ] 3.2 コンフリクト（同一 spec への複数 MODIFIED）を手動レビューで解決
- [ ] 3.3 全 31 changes が `plugins/twl/deltaspec/changes/archive/` に移動済みであることを確認
- [ ] 3.4 root `deltaspec/` ディレクトリを削除（`rm -rf deltaspec/`）

## 4. chain spec-archive ステップ追加（plugins/twl）

- [ ] 4.1 `plugins/twl/scripts/auto-merge.sh` の squash merge 成功後に `twl spec archive $change_id --yes` を追加
- [ ] 4.2 spec-archive 失敗時の WARNING ログ + フォールバック処理を追加
- [ ] 4.3 `plugins/twl/scripts/autopilot-orchestrator.sh` の `archive_done_issues()` から `--skip-specs` を除去
- [ ] 4.4 specs 統合失敗時の `--skip-specs` フォールバック + WARNING ログを追加

## 5. Architecture Context 更新

- [ ] 5.1 `cli/twl/architecture/domain/contexts/spec-management.md` の Constraints に「config.yaml を持つ deltaspec/ のみ有効」を追記
