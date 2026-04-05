## MODIFIED Requirements

### Requirement: cleanup_worker が entry を第2引数として受け取る

`cleanup_worker()` は `entry` を第2引数として受け取り、`resolve_issue_repo_context "$entry"` を呼び出して ISSUE_REPO_PATH を取得しなければならない（SHALL）。

#### Scenario: entry 引数の追加
- **WHEN** `cleanup_worker "$issue" "$entry"` が呼ばれる
- **THEN** 関数内で `resolve_issue_repo_context "$entry"` を実行して ISSUE_REPO_PATH を設定する

### Requirement: クロスリポ環境で正しいリモートに branch 削除を送信する

`cleanup_worker()` は ISSUE_REPO_PATH が設定されている場合、`git -C "$ISSUE_REPO_PATH" push origin --delete "$branch"` を実行しなければならない（SHALL）。

#### Scenario: クロスリポ環境での branch 削除
- **WHEN** entry が "_default" 以外のリポを指し、ISSUE_REPO_PATH が設定されている
- **THEN** `git -C "$ISSUE_REPO_PATH" push origin --delete "$branch" 2>/dev/null || true` を実行する

#### Scenario: デフォルトリポでの branch 削除（後方互換）
- **WHEN** entry が "_default"（ISSUE_REPO_PATH が空）
- **THEN** `git push origin --delete "$branch" 2>/dev/null || true` を従来通り実行する

#### Scenario: branch 未設定の場合はスキップ
- **WHEN** state に branch が記録されていない（空文字）
- **THEN** branch 削除をスキップし、window kill のみ実行する（従来通り）

### Requirement: poll_single が cleanup_worker に entry を渡す

`poll_single()` は `cleanup_worker()` 呼び出し時に entry を第2引数として渡さなければならない（SHALL）。

#### Scenario: poll_single の done/failed ケース
- **WHEN** `poll_single` が status=done または status=failed を検知する
- **THEN** `cleanup_worker "$issue" "$entry"` を呼び出す

#### Scenario: poll_single のタイムアウト
- **WHEN** `poll_single` が MAX_POLL 回に達してタイムアウトする
- **THEN** `cleanup_worker "$issue" "$entry"` を呼び出す

### Requirement: poll_phase が cleanup_worker に entry を渡す

`poll_phase()` は `cleanup_worker()` 呼び出し時に entry を第2引数として渡さなければならない（SHALL）。

#### Scenario: poll_phase の done/failed ケース
- **WHEN** `poll_phase` が issue の status=done または status=failed を初回検知する
- **THEN** `cleanup_worker "$issue" "$entry"` を呼び出す

#### Scenario: poll_phase のタイムアウト
- **WHEN** `poll_phase` が MAX_POLL 回に達し、running の issue を failed に変換する
- **THEN** 変換した各 issue に対して `cleanup_worker "$issue" "$entry"` を呼び出す
