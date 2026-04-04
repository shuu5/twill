## ADDED Requirements

### Requirement: bats フレームワーク導入

bats-core、bats-assert、bats-support を `tests/lib/` に git submodule として導入しなければならない（SHALL）。テスト実行に npm/apt の事前インストールを要求してはならない。

#### Scenario: submodule セットアップ
- **WHEN** `tests/lib/bats-core/` が存在する
- **THEN** `tests/lib/bats-core/bin/bats --version` が正常終了する

#### Scenario: bats-assert 利用可能
- **WHEN** テストファイルが `load '../helpers/common'` をロードする
- **THEN** `assert_success`、`assert_failure`、`assert_output` が利用可能になる

### Requirement: 共通ヘルパー

`tests/bats/helpers/common.bash` に共通 setup/teardown と stub ユーティリティを定義しなければならない（MUST）。

#### Scenario: sandbox 自動作成
- **WHEN** テストの `setup()` が `common_setup` を呼び出す
- **THEN** tmpdir が作成され `$SANDBOX` 変数にパスが設定される

#### Scenario: sandbox 自動削除
- **WHEN** テストの `teardown()` が `common_teardown` を呼び出す
- **THEN** `$SANDBOX` ディレクトリが削除される

#### Scenario: 外部コマンド stub
- **WHEN** テストが `stub_command "gh" "echo mocked"` を呼び出す
- **THEN** sandbox 内の PATH で `gh` が stub に置換される
