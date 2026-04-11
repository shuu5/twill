## 1. worktree-health-check.sh 実装

- [ ] 1.1 `plugins/twl/scripts/worktree-health-check.sh` を新規作成（bare root 検出・全 worktree 列挙・refspec 検査ロジック）
- [ ] 1.2 `--fix` オプションで `git config --replace-all` を使い欠落 refspec を自動修復する処理を実装
- [ ] 1.3 ネットワーク利用可能時の `git ls-remote origin main` vs `git show-ref` tip 比較（タイムアウト 5 秒）を実装
- [ ] 1.4 スクリプトに実行権限を付与し手動実行でスモークテストを実施

## 2. chain-runner.sh worktree-create への refspec 設定追加

- [ ] 2.1 `chain-runner.sh` の `step_worktree_create()` に `python3 -m twl.autopilot.worktree create` 完了後の refspec 設定処理を追加（`git config --replace-all remote.origin.fetch '...'`）
- [ ] 2.2 既存 refspec が正しい場合は重複エントリを作らないことを確認

## 3. autopilot-pilot-precheck への統合

- [ ] 3.1 `plugins/twl/commands/autopilot-pilot-precheck.md` に Step 0 として refspec チェック呼び出し（`worktree-health-check.sh` 使用）を追加
- [ ] 3.2 欠落検出時に `PRECHECK_WARNINGS` へ追加して処理継続（abort しない）を明記

## 4. bats テスト追加

- [ ] 4.1 既存の bats テスト配置場所を確認（`test-fixtures/` or `plugins/twl/tests/`）
- [ ] 4.2 `test_worktree_health_check.bats` を追加：refspec 欠落検出シナリオ（exit 1 + WARN）
- [ ] 4.3 `test_worktree_health_check.bats` に `--fix` シナリオ追加（修復後 exit 0 + 正しい refspec）

## 5. ドキュメント更新

- [ ] 5.1 `plugins/twl/CLAUDE.md` の「Bare repo 構造検証」セクションに第 4 条件（refspec）を追記
