## ADDED Requirements

### Requirement: merge-gate-execute CWD ガード

merge-gate-execute.sh は worktrees/ 配下から実行された場合、処理を拒否しなければならない（MUST）。不変条件B/C を実行時に強制する。

#### Scenario: worktrees/ 配下からの実行拒否
- **WHEN** CWD が `*/worktrees/*` にマッチする
- **THEN** エラーメッセージを stderr に出力し exit 1 で終了する

#### Scenario: main worktree からの実行許可
- **WHEN** CWD が worktrees/ 配下でない（main/ 等）
- **THEN** 通常通り処理を続行する

#### Scenario: ガード位置
- **WHEN** スクリプトが実行される
- **THEN** 環境変数バリデーション後、MODE 判定前に CWD チェックが実行されなければならない（SHALL）
