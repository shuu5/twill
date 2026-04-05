## ADDED Requirements

### Requirement: cleanup_worker ヘルパー関数

orchestrator に `cleanup_worker(issue)` 関数を追加しなければならない（SHALL）。この関数は tmux window kill とリモートブランチ削除を実行しなければならない（SHALL）。

#### Scenario: tmux window の kill
- **WHEN** `cleanup_worker "$issue"` が呼ばれる
- **THEN** `tmux kill-window -t "ap-#${issue}"` を実行し、失敗時は無視する

#### Scenario: リモートブランチの削除
- **WHEN** `cleanup_worker "$issue"` が呼ばれ、state に branch が記録されている
- **THEN** `git push origin --delete "$branch"` を実行し、失敗時は無視する

#### Scenario: branch 未設定の場合
- **WHEN** `cleanup_worker "$issue"` が呼ばれ、state に branch が空
- **THEN** リモートブランチ削除をスキップし、window kill のみ実行する

### Requirement: poll_single done/failed 時の cleanup

`poll_single` は done または failed を検知した時点で `cleanup_worker` を呼ばなければならない（SHALL）。

#### Scenario: poll_single で done 検知
- **WHEN** `poll_single` がポーリング中に status=done を取得する
- **THEN** `cleanup_worker "$issue"` を実行してから `return 0` する

#### Scenario: poll_single で failed 検知
- **WHEN** `poll_single` がポーリング中に status=failed を取得する
- **THEN** `cleanup_worker "$issue"` を実行してから `return 0` する

#### Scenario: poll_single で merge-ready 検知
- **WHEN** `poll_single` がポーリング中に status=merge-ready を取得する
- **THEN** `cleanup_worker` を呼ばず `return 0` する（merge-gate が後続で cleanup する）

### Requirement: poll_phase done/failed 時の cleanup

`poll_phase` は各 issue の done または failed を初回検知した時点で `cleanup_worker` を呼ばなければならない（SHALL）。

#### Scenario: poll_phase で done 検知（初回）
- **WHEN** `poll_phase` がポーリング中に issue の status=done を取得する
- **THEN** `cleanup_worker "$issue"` を実行する

#### Scenario: poll_phase で failed 検知（初回）
- **WHEN** `poll_phase` がポーリング中に issue の status=failed を取得する
- **THEN** `cleanup_worker "$issue"` を実行する

#### Scenario: cleanup の冪等性
- **WHEN** `cleanup_worker` が同じ issue に対して複数回呼ばれる
- **THEN** 2回目以降は `tmux kill-window` が失敗しても `|| true` で無視する

### Requirement: poll タイムアウト時の cleanup

`poll_phase` はタイムアウト時に `status=failed` を設定した各 issue に対して `cleanup_worker` を呼ばなければならない（SHALL）。

#### Scenario: タイムアウト時の cleanup
- **WHEN** `poll_phase` が MAX_POLL 回に達し、running の issue を failed に変換する
- **THEN** 変換した各 issue に対して `cleanup_worker "$issue"` を実行する
