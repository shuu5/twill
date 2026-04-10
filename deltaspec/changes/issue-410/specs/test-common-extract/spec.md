## ADDED Requirements

### Requirement: test-common.sh 共通ヘルパーの提供

`plugins/twl/tests/helpers/test-common.sh` を新規作成し、テストスクリプト間で共通のヘルパー関数・カウンター・サマリー出力を提供しなければならない（SHALL）。

#### Scenario: ヘルパー関数の提供
- **WHEN** テストスクリプトが `source` で `test-common.sh` を読み込む
- **THEN** `assert_file_exists`, `assert_file_contains`, `assert_file_not_contains`, `run_test`, `run_test_skip` 関数が利用可能になる

#### Scenario: カウンターの初期化
- **WHEN** `test-common.sh` が source される
- **THEN** `PASS=0`, `FAIL=0`, `SKIP=0`, `ERRORS=()` が初期化される

#### Scenario: サマリー出力
- **WHEN** `print_summary` 関数が呼び出される
- **THEN** 通過・失敗・スキップ件数と失敗テスト名の一覧が出力され、`$FAIL` を exit code として返す

## MODIFIED Requirements

### Requirement: skillmd-pilot-fixes.test.sh の行数削減

`plugins/twl/tests/scenarios/skillmd-pilot-fixes.test.sh` は共通ヘルパーを `test-common.sh` から source し、300 行以下でなければならない（MUST）。既存のテストロジックは変更してはならない（SHALL NOT）。

#### Scenario: 行数閾値の遵守
- **WHEN** `skillmd-pilot-fixes.test.sh` がリファクタリングされる
- **THEN** `wc -l` で 300 行以下になる

#### Scenario: テスト結果の非退行
- **WHEN** リファクタリング後のスクリプトを実行する
- **THEN** 既存の 19 テストが全て同じ結果（PASS/FAIL/SKIP）を返す
