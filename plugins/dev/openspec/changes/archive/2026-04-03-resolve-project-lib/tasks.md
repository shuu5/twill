## 1. 共通ライブラリ作成

- [x] 1.1 `scripts/lib/` ディレクトリを作成する
- [x] 1.2 `scripts/lib/resolve-project.sh` を新規作成し、`resolve_project` 関数を実装する（stdout: `project_num project_id owner repo_name repo_fullname`、mapfile パターン使用）
- [x] 1.3 `resolve_project` 内でエラー時に stderr 出力 + 非ゼロ終了コードを実装する

## 2. chain-runner.sh のリファクタリング

- [x] 2.1 `step_board_status_update()` を `resolve_project` を使用するようにリファクタリングする
- [x] 2.2 `step_board_archive()` を `resolve_project` を使用するようにリファクタリングする
- [x] 2.3 重複していた GraphQL クエリ定義および検索ループを削除する

## 3. 個別スクリプトのリファクタリング

- [x] 3.1 `scripts/project-board-archive.sh` を `resolve_project` を source して使用するようにリファクタリングする
- [x] 3.2 `scripts/project-board-backfill.sh` を `resolve_project` を source して使用するようにリファクタリングする
- [x] 3.3 `scripts/autopilot-plan-board.sh` の `resolve_board()` を `resolve_project` に委譲するようにリファクタリングする

## 4. deps.yaml 更新と検証

- [x] 4.1 `deps.yaml` に `scripts/lib/resolve-project.sh` のエントリを追加する
- [x] 4.2 `loom check` を実行してエラーがないことを確認する
- [x] 4.3 `loom update-readme` を実行して README を更新する
