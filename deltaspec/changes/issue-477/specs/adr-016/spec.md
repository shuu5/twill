## ADDED Requirements

### Requirement: ADR-016 ファイル存在

`plugins/twl/architecture/decisions/ADR-016-test-target-real-issues.md` が存在しなければならない（SHALL）。

#### Scenario: ファイル存在確認
- **WHEN** `plugins/twl/architecture/decisions/` ディレクトリを確認する
- **THEN** `ADR-016-test-target-real-issues.md` が存在する

### Requirement: 3 選択肢比較表

ADR-016 は test-target 戦略の 3 選択肢比較表と選定根拠を含まなければならない（MUST）。選定は「専用テストリポ」でなければならない（SHALL）。

#### Scenario: 比較表確認
- **WHEN** ADR-016 を読む
- **THEN** 専用テストリポ / 実リポ test ラベル / mock GitHub API の 3 選択肢比較表が含まれる
- **THEN** 「専用テストリポを採用する」という決定と選定根拠が含まれる

### Requirement: co-self-improve 統合フロー

ADR-016 は co-self-improve の `--real-issues` モードとの統合フロー図を含まなければならない（MUST）。

#### Scenario: 統合フロー確認
- **WHEN** ADR-016 を読む
- **THEN** `--real-issues` モードの Step 1 分岐フローが含まれる
- **THEN** 専用テストリポへの Issue 起票とautopilot 起動手順が含まれる

### Requirement: クリーンアップフロー

ADR-016 はテスト完了後のクリーンアップフロー（PR close → Issue close → branch 削除）を含まなければならない（MUST）。クリーンアップは冪等でなければならない（SHALL）。

#### Scenario: クリーンアップフロー確認
- **WHEN** ADR-016 を読む
- **THEN** PR close → Issue close → branch 削除の順序が明記されている
- **THEN** 各ステップの冪等性設計（404 無視、既クローズは noop 等）が含まれる

### Requirement: リポジトリ管理責務帰属

ADR-016 はテストリポ作成・管理の責務帰属を決定しなければならない（MUST）。

#### Scenario: 責務帰属確認
- **WHEN** ADR-016 を読む
- **THEN** `test-project-init --mode real-issues` が責務を持つと明記されている
- **THEN** 月次ローテーション（`twill-test-<YYYYMM>`）ポリシーが含まれる
