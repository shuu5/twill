## Requirements

### Requirement: TWILL_REPO_ROOT export

`autopilot-orchestrator.sh` は `launch_worker()` 内の `effective_project_dir` 確定直後に `TWILL_REPO_ROOT` を `PROJECT_DIR` から export しなければならない（SHALL）。

#### Scenario: worktree 作成時に TWILL_REPO_ROOT が設定される
- **WHEN** `launch_worker()` が呼び出され、`effective_project_dir` が確定した後
- **THEN** `TWILL_REPO_ROOT` 環境変数が `${PROJECT_DIR}` の値で export される

#### Scenario: ISSUE_REPO_PATH 設定時も TWILL_REPO_ROOT は twill モノリポルートを指す
- **WHEN** クロスリポジトリ実行で `ISSUE_REPO_PATH` が設定されている
- **THEN** `TWILL_REPO_ROOT` は `PROJECT_DIR`（twill モノリポルート）を指し、`ISSUE_REPO_PATH` とは独立している

### Requirement: CRG symlink 参照先を TWILL_REPO_ROOT ベースに変更

CRG symlink 作成ロジックは `TWILL_REPO_ROOT` 環境変数を使って参照先を決定しなければならない（MUST）。`effective_project_dir` を直接使ってはならない。

#### Scenario: feature worktree への CRG symlink 作成
- **WHEN** `worktree_dir` が main worktree でない feature worktree を指す
- **THEN** `${TWILL_REPO_ROOT}/main/.code-review-graph` へのシンボリックリンクが `worktree_dir/.code-review-graph` に作成される

#### Scenario: main worktree への自己参照 symlink を作成しない
- **WHEN** `worktree_dir` が `${TWILL_REPO_ROOT}/main` と等しい（末尾スラッシュ strip 後の文字列比較）
- **THEN** CRG symlink が作成されない（自己参照防止）

### Requirement: _is_main 判定を文字列比較に変更

main worktree 判定は `realpath` を使わず、`${TWILL_REPO_ROOT}/main` との文字列比較（末尾スラッシュ strip 済み）で行わなければならない（MUST）。

#### Scenario: main worktree の正確な判定
- **WHEN** `worktree_dir` が `/path/to/twill/main` または `/path/to/twill/main/` の形式
- **THEN** `_is_main=1` と判定され、CRG symlink が作成されない

#### Scenario: feature worktree は main と判定されない
- **WHEN** `worktree_dir` が `/path/to/twill/worktrees/feat/xxx` の形式
- **THEN** `_is_main=0` と判定され、CRG symlink 作成処理が続行される

## Requirement: realpath ベースのガード削除

旧来の `realpath` ベースの `_is_main` 判定コード（旧 line 328）を削除しなければならない（SHALL）。

#### Scenario: realpath ガードが存在しない
- **WHEN** `autopilot-orchestrator.sh` の CRG symlink 作成ブロックを確認する
- **THEN** `realpath` を使った `_is_main` 判定が存在しない
