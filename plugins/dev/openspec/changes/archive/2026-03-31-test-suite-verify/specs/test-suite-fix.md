## MODIFIED Requirements

### Requirement: テストスイート全件 PASS

テストスイート（37 bats + 37 scenario）は全件 PASS しなければならない（SHALL）。コマンド形式リファクタ（COMMAND.md → \<name\>.md）に追従し、失敗テストを修正する。

#### Scenario: ベースライン記録
- **WHEN** テストスイートを初回実行する
- **THEN** PASS/FAIL 数を Issue #43 のコメントに記録しなければならない（MUST）

#### Scenario: bats テスト全件 PASS
- **WHEN** `tests/run-tests.sh` を実行する
- **THEN** 37 bats テストが全件 PASS しなければならない（SHALL）

#### Scenario: scenario テスト全件 PASS
- **WHEN** `tests/run-tests.sh` を実行する
- **THEN** 37 scenario テストが全件 PASS しなければならない（SHALL）

#### Scenario: 失敗数超過時の分割
- **WHEN** 失敗テストが10件を超える
- **THEN** ベースライン記録+分類のみを行い、修正は別 Issue に分割しなければならない（MUST）

### Requirement: hooks 動作確認

PostToolUseFailure hooks が期待通りに動作しなければならない（SHALL）。テスト実行中にエラーが検出されないことを確認する。

#### Scenario: hooks エラーなし
- **WHEN** テストスイートを実行する
- **THEN** PostToolUseFailure hooks がエラーなく動作しなければならない（SHALL）

### Requirement: chain generate --check PASS

`chain generate --check` が PASS しなければならない（SHALL）。chain 定義の整合性を検証する。

#### Scenario: chain チェック PASS
- **WHEN** `chain generate --check` を実行する
- **THEN** 全 chain 定義がチェックを PASS しなければならない（SHALL）
