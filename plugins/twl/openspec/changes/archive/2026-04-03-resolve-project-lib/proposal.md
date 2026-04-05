## Why

Project Board 操作に必要な「リポジトリにリンクされた Project を GraphQL で検出するロジック」が5箇所に重複しており、変更時に全箇所を同期する必要があるため、メンテナンスコストが高くバグの温床となっている。

## What Changes

- `scripts/lib/resolve-project.sh` を新規作成（共通の `resolve_project` 関数）
- `scripts/chain-runner.sh` の `step_board_status_update()` および `step_board_archive()` をリファクタリング
- `scripts/project-board-archive.sh` をリファクタリング
- `scripts/project-board-backfill.sh` をリファクタリング
- `scripts/autopilot-plan-board.sh` の `resolve_board()` をリファクタリング
- `deps.yaml` を更新

## Capabilities

### New Capabilities

- `resolve_project` 共通関数: `stdout` に `project_num project_id owner repo_name repo_fullname` の5値を返す
- `mapfile -t` パターンによる word-split 安全な Project リスト取得
- Project が0件の場合の早期 return
- GraphQL クエリの pretty format 統一

### Modified Capabilities

- 各呼び出し元は `resolve_project` を `source` して `read` で必要な変数のみ受け取る形式に変更
- `autopilot-plan-board.sh` の `resolve_board()` は内部実装を `resolve_project` に委譲

## Impact

- 変更ファイル: `scripts/chain-runner.sh`, `scripts/project-board-archive.sh`, `scripts/project-board-backfill.sh`, `scripts/autopilot-plan-board.sh`
- 新規ファイル: `scripts/lib/resolve-project.sh`
- 外部 API 依存: `gh repo view`, `gh project list`, GitHub GraphQL API（変更なし）
- 他スクリプトへの影響: なし（インターフェースは維持）
