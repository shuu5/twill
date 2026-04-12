## Why

bare repo + worktree 構造において、`autopilot-orchestrator.sh` の CRG symlink 作成ロジックが `realpath` ベースのガードに依存しているため、コンテキスト（symlink 経由 / 直接アクセス）によって `realpath` の結果が変わり main worktree への自己参照 symlink が発生しうる。`TWILL_REPO_ROOT` 環境変数方式に移行することで構造依存を排除し、確実な main worktree 判定を実現する。

## What Changes

- `plugins/twl/scripts/autopilot-orchestrator.sh` の `setup_worktree()`（または同等の worktree 作成処理）冒頭で `TWILL_REPO_ROOT` を `effective_project_dir` から export するロジックを追加
- CRG symlink 作成ロジックを `TWILL_REPO_ROOT` ベースの参照（`${TWILL_REPO_ROOT}/main/.code-review-graph`）に変更
- main worktree 判定（`_is_main`）を `${TWILL_REPO_ROOT}/main` との文字列比較に簡素化（末尾スラッシュ strip 済み）
- 既存の `realpath` ベースのガード（旧 line 324-329）を削除

## Capabilities

### New Capabilities

なし（既存動作の保証強化・脆弱性解消のみ）

### Modified Capabilities

- **CRG symlink 作成**: `realpath` ベースから `TWILL_REPO_ROOT` 環境変数ベースに変更。main worktree への自己参照 symlink が発生しなくなる
- **`_is_main` 判定**: realpath 一致から文字列比較（末尾スラッシュ strip）に変更。マウントポイントやバインドマウントの影響を受けなくなる

## Impact

- **影響ファイル**: `plugins/twl/scripts/autopilot-orchestrator.sh`
- **スコープ外**: `issue-lifecycle-orchestrator.sh`、`cld-spawn` env 伝搬、クロスリポジトリ時の `TWILL_REPO_ROOT` 設定（別 Issue で対応）
- **クロスリポ**: `ISSUE_REPO_PATH` が設定された場合も `TWILL_REPO_ROOT` は常に twill モノリポルートを指す。独立性を維持
