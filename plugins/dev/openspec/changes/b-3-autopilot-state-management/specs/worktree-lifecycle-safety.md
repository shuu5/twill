## ADDED Requirements

### Requirement: worktree 削除の Pilot 専任ルール

worktree-delete.sh は Pilot（main/ から実行）専任とし、Worker（worktrees/ 内から実行）による呼び出しを拒否しなければならない（SHALL）。

#### Scenario: Pilot からの worktree 削除
- **WHEN** CWD が `main/` 配下で `worktree-delete.sh feat/42-xxx` が実行される
- **THEN** worktree と対応するブランチが削除される

#### Scenario: Worker からの worktree 削除拒否
- **WHEN** CWD が `worktrees/feat/42-xxx/` 配下で `worktree-delete.sh feat/42-xxx` が実行される
- **THEN** Worker からの削除は不変条件 B に違反するため、exit 1 でエラー終了しメッセージを表示する

#### Scenario: 自身の worktree 削除拒否
- **WHEN** CWD が `worktrees/feat/42-xxx/` 配下で `worktree-delete.sh feat/42-xxx` が実行される（自身の worktree を削除しようとする）
- **THEN** 自身の CWD が削除対象に含まれるため、exit 1 でエラー終了する

### Requirement: crash 検知によるステータス遷移

ポーリング中に Worker の crash（tmux ペイン消失）を検知した場合、issue-{N}.json の status を `failed` に遷移しなければならない（MUST）。

#### Scenario: tmux ペイン消失の検知
- **WHEN** ポーリング中に `tmux list-panes -t <window>` が失敗し、対応する issue-{N}.json の status が `running` である
- **THEN** issue-{N}.json の status が `failed` に遷移し、failure フィールドに crash 情報（message, step, timestamp）が記録される

#### Scenario: 正常終了との区別
- **WHEN** tmux ペインが消失し、対応する issue-{N}.json の status が `merge-ready` である
- **THEN** Worker は正常に merge-ready を宣言して終了したため、crash として扱わない

### Requirement: merge 後の worktree クリーンアップ

merge-gate PASS 後、Pilot は worktree 削除と tmux window kill を実行しなければならない（SHALL）。

#### Scenario: merge 成功後のクリーンアップ
- **WHEN** issue-{N}.json の status が `done` に遷移した後
- **THEN** Pilot が `worktree-delete.sh` で worktree を削除し、`tmux kill-window -t <window>` で window を終了する

#### Scenario: merge-gate REJECT 後の worktree 保持
- **WHEN** merge-gate が REJECT を返し、retry_count < 1 である
- **THEN** worktree は削除せず保持する（fix-phase で再利用するため）
