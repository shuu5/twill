## 1. ADR-016 ファイル作成

- [x] 1.1 `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` を作成する
- [x] 1.2 3 選択肢比較表（専用テストリポ / 実リポ test ラベル / mock GitHub API）を含める
- [x] 1.3 専用テストリポ選定根拠を記述する
- [x] 1.4 co-self-improve との統合フロー（`--real-issues` モード）を記述する
- [x] 1.5 クリーンアップフロー（PR close → Issue close → branch 削除）を記述する
- [x] 1.6 リポジトリ管理責務帰属（`test-project-init --mode real-issues` 拡張）を決定する

## 2. 検証

- [ ] 2.1 ADR-016 ファイルが `plugins/twl/architecture/decisions/` に存在することを確認する
- [ ] 2.2 #477 の全受け入れ基準を満たしていることを確認する
