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
- **WHEN** `realpath -m "$worktree_dir"` が `realpath -m "${TWILL_REPO_ROOT}/main"` と等しい
- **THEN** CRG symlink が作成されない（自己参照防止）

### Requirement: _is_main 判定に realpath 正規化を使用

main worktree 判定は `realpath -m` で両パスを正規化して比較しなければならない（MUST）。`realpath` が失敗した場合は元のパス文字列でフォールバック比較を行う。これにより symlink・相対パスを含む環境でも正確に判定できる（#605）。

#### Scenario: main worktree の正確な判定（realpath 使用）
- **WHEN** `worktree_dir` が `/path/to/twill/main` または symlink 経由のパス
- **THEN** `realpath -m "$worktree_dir"` と `realpath -m "${TWILL_REPO_ROOT%/}/main"` が一致し、CRG symlink が作成されない

#### Scenario: feature worktree は main と判定されない
- **WHEN** `worktree_dir` が `/path/to/twill/worktrees/feat/xxx` の形式
- **THEN** realpath 正規化後も値が異なり、CRG symlink 作成処理が続行される

#### Scenario: realpath 失敗時のフォールバック
- **WHEN** `realpath -m` コマンドが失敗する環境
- **THEN** 元のパス文字列でのフォールバック比較が実行され、処理が継続する

### Requirement: main/.code-review-graph が symlink の場合は即座に削除

`${TWILL_REPO_ROOT}/main/.code-review-graph` がシンボリックリンクの場合、worktree 判定より前に削除して修復しなければならない（SHALL）。LLM による誤 symlink 作成の自己参照根絶のため（#674）。

#### Scenario: main/.code-review-graph symlink の自動修復
- **WHEN** `${TWILL_REPO_ROOT}/main/.code-review-graph` がシンボリックリンクである
- **THEN** `rm -f` で即座に削除され、`"CRG: main/.code-review-graph が symlink — 削除して修復しました (#674)"` がログに記録される
