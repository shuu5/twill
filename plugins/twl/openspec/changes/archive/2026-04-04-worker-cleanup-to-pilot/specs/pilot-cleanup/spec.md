## ADDED Requirements

### Requirement: Pilot側クリーンアップシーケンス実行

autopilot Orchestratorは、merge-gate成功後にWorkerリソースを以下の順序でクリーンアップしなければならない（SHALL）。

順序: tmux kill-window → worktree-delete.sh → git push origin --delete

#### Scenario: merge-gate成功後のクリーンアップ正常系
- **WHEN** autopilot-orchestrator.shがIssue NのPRのmerge-gate PASSを検出する
- **THEN** `tmux kill-window -t "ap-#${ISSUE_NUM}"` → `worktree-delete.sh` → `git push origin --delete "${BRANCH}"` の順で実行される

#### Scenario: tmux windowが既に存在しない場合の冪等動作
- **WHEN** クリーンアップ開始時にtmux windowが既に存在しない
- **THEN** tmuxステップはエラーを無視して正常扱いとし、次のworktree削除ステップへ進む

#### Scenario: worktreeが既に削除済みの場合の冪等動作
- **WHEN** クリーンアップ開始時にworktreeが既に削除済み
- **THEN** worktree-delete.shは正常終了し、次のリモートブランチ削除ステップへ進む

#### Scenario: クリーンアップステップ失敗時の継続
- **WHEN** worktree削除ステップが失敗する（例: パーミッションエラー）
- **THEN** 警告メッセージを出力し、残りのステップ（リモートブランチ削除）を続行する

## MODIFIED Requirements

### Requirement: merge-gate-execute.shのautopilot分岐

`scripts/merge-gate-execute.sh`は、autopilot環境下でのmerge成功後にクリーンアップ処理をスキップしなければならない（SHALL）。

autopilot判定条件: `${AUTOPILOT_DIR:-.autopilot}/issues/issue-${ISSUE_NUM}.json` が存在する場合。

#### Scenario: autopilot時のクリーンアップスキップ
- **WHEN** merge-gate-execute.shがmerge成功後のクリーンアップフェーズに入り、AUTOPILOT_DIRが設定されissue-{N}.jsonが存在する
- **THEN** worktree削除 / リモートブランチ削除 / tmux kill-windowをスキップし、Pilotへの委譲メッセージを出力する

#### Scenario: 非autopilot時の従来動作維持
- **WHEN** merge-gate-execute.shがautopilot環境外（issue-{N}.jsonが存在しない）で実行される
- **THEN** 従来どおりmerge-gate-execute.sh自身がクリーンアップを実行する

### Requirement: autopilot-phase-execute.mdのtmux kill-window重複排除

`commands/autopilot-phase-execute.md`は、autopilot-orchestrator.shがcleanupを担当するため、自身のtmux kill-window呼び出しを削除しなければならない（SHALL）。

#### Scenario: phase-executeのtmux kill-window重複排除
- **WHEN** Issue N の merge-gate が完了する
- **THEN** autopilot-phase-execute.md内のtmux kill-window呼び出しは行われず、cleanup一元化されたautopilot-orchestrator.shが処理する

## ADDED Requirements

### Requirement: クロスリポジトリcleanup対応

autopilot Orchestratorは、クロスリポジトリIssueのリモートブランチを正しいリポジトリに対して削除しなければならない（SHALL）。

#### Scenario: クロスリポジトリのリモートブランチ削除
- **WHEN** issue-{N}.jsonに`repo`フィールドが存在し、currentリポジトリと異なるリポジトリを示している
- **THEN** 対象リポジトリのディレクトリに移動（`-C <repo_path>`相当）してから`git push origin --delete "${BRANCH}"`を実行する

#### Scenario: 同一リポジトリIssueの通常削除
- **WHEN** issue-{N}.jsonの`repo`フィールドが存在しないか、currentリポジトリと一致する
- **THEN** カレントディレクトリで`git push origin --delete "${BRANCH}"`を実行する
