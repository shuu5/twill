## 1. SKILL.MD 再生成

- [x] 1.1 loom chain generate --write --all を worktree 内で実行し全 SKILL.md を再生成
- [x] 1.2 loom check で chain 整合性エラーが 0 件であることを確認
- [x] 1.3 再生成された SKILL.md の差分を確認しコミット

## 2. Switchover 検証環境構築

- [x] 2.1 switchover.sh check を実行し事前チェック通過を確認
- [x] 2.2 switchover.sh switch --new で loom-plugin-dev に切替
- [x] 2.3 symlink が loom-plugin-dev を指していることを確認

## 3. S1: workflow-setup 検証

- [x] 3.1 loom-plugin-test にテスト用 Issue を作成
- [x] 3.2 loom-plugin-test で /dev:workflow-setup #3 を実行
- [x] 3.3 worktree 作成 → OpenSpec → ac-extract の自律完了を確認
- [x] 3.4 pr-cycle chain にチェックポイント不在を発見し修正（12コマンド追加）

## 4. S2: workflow-pr-cycle 検証

- [x] 4.1 S1 の成果物に対して /dev:workflow-pr-cycle を実行
- [x] 4.2 ts-preflight → phase-review → scope-judge → pr-test → report の chain 完了を確認
- [x] 4.3 PR コメントにレビュー結果投稿を確認
- [x] 4.4 テスト PASS (4/4)、CRITICAL: 1（spec）、WARNING: 9

## 5. 切替固定化とレポート

- [x] 5.1 検証完了後 symlink を loom-plugin-dev のまま維持（rollback 不要）
- [ ] 5.2 検証レポートを作成（各シナリオの結果、修正内容、残存問題）
- [ ] 5.3 PR 作成 → マージ
