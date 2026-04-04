## MODIFIED Requirements

### Requirement: cleanup_worker の REPO_MODE 条件分岐

`cleanup_worker` 関数は、worktree削除ステップ（`worktree-delete.sh` 呼び出し）の前に `REPO_MODE` を自動判定しなければならない（SHALL）。`REPO_MODE=standard` の場合、`worktree-delete.sh` の呼び出しをスキップしなければならない（SHALL）。

#### Scenario: standard repo でのクリーンアップ
- **WHEN** `REPO_MODE=standard`（`git rev-parse --git-dir` が `.git` を返す）環境で `cleanup_worker` が呼ばれる
- **THEN** `worktree-delete.sh` を呼び出さずにクリーンアップを続行し、警告を出力しない

#### Scenario: bare repo（worktree モード）でのクリーンアップ
- **WHEN** `REPO_MODE=worktree`（`git rev-parse --git-dir` が `.git` 以外を返す）環境で `cleanup_worker` が呼ばれる
- **THEN** 従来どおり `worktree-delete.sh` を呼び出す

#### Scenario: ブランチが未設定の場合
- **WHEN** state から branch が取得できない（空文字列）
- **THEN** `REPO_MODE` に関わらず worktree 削除ステップをスキップする（既存の動作を維持する）
