## ADDED Requirements

### Requirement: resolve_project 共通関数の作成

`scripts/lib/resolve-project.sh` に `resolve_project` 関数を作成しなければならない（SHALL）。この関数は GitHub GraphQL API を使用してリポジトリにリンクされた Project を検出し、`project_num project_id owner repo_name repo_fullname` の5値を stdout に出力しなければならない（SHALL）。

#### Scenario: 正常系 - リンク済み Project が存在する場合
- **WHEN** `resolve_project` を呼び出し、リポジトリにリンクされた Project が存在する
- **THEN** stdout に `project_num project_id owner repo_name repo_fullname` の5値が空白区切りで出力され、終了コード0で返る

#### Scenario: タイトルマッチ優先
- **WHEN** 複数の Project がリポジトリにリンクされており、そのうち1つのタイトルにリポ名が含まれる
- **THEN** タイトルマッチした Project が優先して返される

#### Scenario: エラー系 - Project が存在しない場合
- **WHEN** `resolve_project` を呼び出し、リポジトリにリンクされた Project が存在しない
- **THEN** stderr にエラーメッセージを出力し、非ゼロ終了コードで返る

#### Scenario: mapfile による word-split 安全化
- **WHEN** `gh project list` の出力に複数の Project 番号が含まれる
- **THEN** `mapfile -t` パターンで配列化され、word-split なしに安全にループ処理される

## MODIFIED Requirements

### Requirement: chain-runner.sh の board 操作関数のリファクタリング

`step_board_status_update()` および `step_board_archive()` は `resolve_project` を使用するようにリファクタリングしなければならない（SHALL）。重複したプロジェクト検出ロジックを削除し、共通関数に委譲しなければならない（MUST）。

#### Scenario: step_board_status_update の動作継続
- **WHEN** `step_board_status_update` が呼び出される
- **THEN** 既存の動作（Project Board のステータスを "In Progress" に更新）が維持される

#### Scenario: step_board_archive の動作継続
- **WHEN** `step_board_archive` が呼び出される
- **THEN** 既存の動作（Issue のアーカイブ）が維持される

### Requirement: 各スクリプトの resolve_project 採用

`scripts/project-board-archive.sh`、`scripts/project-board-backfill.sh`、`scripts/autopilot-plan-board.sh` は `resolve_project` を source して使用するようにリファクタリングしなければならない（SHALL）。

#### Scenario: project-board-archive.sh の動作継続
- **WHEN** `project-board-archive.sh` が実行される
- **THEN** 既存の動作（Issue のアーカイブ）が維持される

#### Scenario: project-board-backfill.sh の動作継続
- **WHEN** `project-board-backfill.sh` が実行される
- **THEN** 既存の動作（Project Board のバックフィル）が維持される

#### Scenario: autopilot-plan-board.sh の動作継続
- **WHEN** `autopilot-plan-board.sh` が実行される
- **THEN** 既存の動作（Autopilot 計画の Project Board 反映）が維持される

### Requirement: deps.yaml への lib エントリ追加

`deps.yaml` に `scripts/lib/resolve-project.sh` のエントリを追加しなければならない（SHALL）。

#### Scenario: deps.yaml 更新
- **WHEN** `loom check` を実行する
- **THEN** `scripts/lib/resolve-project.sh` が deps.yaml に登録されており、エラーが出ない
