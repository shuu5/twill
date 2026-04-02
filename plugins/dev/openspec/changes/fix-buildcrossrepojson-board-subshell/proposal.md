## Why

`fetch_board_issues()` (L183) が `_build_cross_repo_json()` をコマンド置換 `$()` 内で呼び出しているため、関数内で設定されるグローバル変数（`CROSS_REPO`, `REPO_OWNERS`, `REPO_NAMES`, `REPO_PATHS`, `REPOS_JSON`）がサブシェルで消失し、`parse_issues()` に伝搬しない。`--board` モードでクロスリポジトリ Issue を含む Board を処理する際に `Error: 不明な repo_id` で失敗する。

## What Changes

- `_build_cross_repo_json()` の戻り値を stdout から グローバル変数 `BUILD_RESULT` に変更
- `fetch_board_issues()` でコマンド置換を廃止し、直接呼び出しに変更
- クロスリポジトリ Board のシナリオテストを追加

## Capabilities

### New Capabilities

なし（バグ修正）

### Modified Capabilities

- `--board` モードでクロスリポジトリ Issue を含む Board を正しく処理できるようになる

## Impact

- **対象ファイル**: `scripts/autopilot-plan-board.sh` (L119-186)
- **影響範囲**: `--board` モードのクロスリポジトリ処理のみ。単一リポジトリ Board は変更なし
- **テスト**: 既存の `autopilot-plan-board-detect.bats`, `autopilot-plan-board-fetch.bats` の PASS 維持 + 新規テスト追加
