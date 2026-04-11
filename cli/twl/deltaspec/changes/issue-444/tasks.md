## 1. ADR-016 ドキュメント作成

- [x] 1.1 `plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` を新規作成する
- [x] 1.2 3 選択肢（専用リポ / 実リポ test ラベル / mock GitHub API）の比較表を記載する
- [x] 1.3 Decision（専用リポ採用）と選定根拠を記載する
- [x] 1.4 Consequences（リスク・トレードオフ）を記載する

## 2. co-self-improve 統合フロー設計

- [x] 2.1 `--real-issues` モードの統合フロー図を ADR-016 に記載する（リポ作成→Issue起票→autopilot→observe→cleanup）
- [x] 2.2 co-self-improve SKILL.md の Step 1 への分岐追加箇所を特定し、設計内容として ADR に記載する

## 3. クリーンアップ設計

- [x] 3.1 テスト後クリーンアップフロー（PR close / Issue close / branch 削除）を ADR-016 に記載する
- [x] 3.2 クリーンアップの冪等性（再実行可否）の設計方針を ADR-016 に記載する

## 4. リポジトリ管理責務の決定

- [x] 4.1 `test-project-init --mode real-issues` 拡張として責務帰属を ADR-016 に記載する
- [x] 4.2 テストリポのライフサイクル管理ルール（増殖防止ポリシー）を ADR-016 に記載する
