## MODIFIED Requirements

### Requirement: _build_cross_repo_json グローバル変数伝搬の修正

`_build_cross_repo_json()` は stdout 出力ではなくグローバル変数 `BUILD_RESULT` で issue_list を返さなければならない（SHALL）。`fetch_board_issues()` はコマンド置換 `$()` を使わず直接呼び出しを行わなければならない（MUST）。

#### Scenario: クロスリポジトリ Board で CROSS_REPO が伝搬する
- **WHEN** `--board` モードで異なるリポジトリの Issue を含む Board を処理した場合
- **THEN** `CROSS_REPO` が `true` に設定され、`REPO_OWNERS`, `REPO_NAMES`, `REPO_PATHS`, `REPOS_JSON` が `parse_issues()` に正しく伝搬し、plan.yaml の repos セクションにクロスリポジトリ情報が出力される

#### Scenario: 単一リポジトリ Board の回帰なし
- **WHEN** `--board` モードで現在のリポジトリのみの Issue を含む Board を処理した場合
- **THEN** 既存と同一の plan.yaml が生成され、`CROSS_REPO` は変更されない

#### Scenario: BUILD_RESULT にスペース区切りの issue_list が格納される
- **WHEN** `_build_cross_repo_json()` が呼び出された後
- **THEN** `BUILD_RESULT` にスペース区切りの issue_list 文字列（例: `"42 43 other-repo#56"`）が格納される

## ADDED Requirements

### Requirement: クロスリポジトリ Board シナリオテスト

クロスリポジトリ Issue を含む Board のテストケースを追加しなければならない（MUST）。

#### Scenario: クロスリポジトリ Issue が plan.yaml に repos セクション付きで出力される
- **WHEN** Board に `shuu5/loom-plugin-dev#42` と `shuu5/other-repo#56` が存在する場合
- **THEN** plan.yaml に `42` と `other-repo#56` が含まれ、repos セクションに `other-repo` の owner/name 情報が出力される

#### Scenario: 既存テストが全て PASS を維持する
- **WHEN** `autopilot-plan-board-detect.bats` および `autopilot-plan-board-fetch.bats` を実行した場合
- **THEN** 全テストが PASS する
