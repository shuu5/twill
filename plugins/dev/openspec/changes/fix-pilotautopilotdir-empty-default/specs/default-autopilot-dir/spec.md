## MODIFIED Requirements

### Requirement: 単一リポジトリ時の PILOT_AUTOPILOT_DIR デフォルト値設定

`resolve_issue_repo_context()` は、単一リポジトリ（`repo_id == '_default'`）の場合に `PILOT_AUTOPILOT_DIR` を Pilot の `$AUTOPILOT_DIR` に設定しなければならない（SHALL）。

#### Scenario: 単一リポジトリで resolve_issue_repo_context を呼び出す
- **WHEN** `repo_id` が `_default` である
- **THEN** `PILOT_AUTOPILOT_DIR` は `$AUTOPILOT_DIR` の値に設定される

#### Scenario: クロスリポジトリで resolve_issue_repo_context を呼び出す
- **WHEN** `repo_id` が `_default` でなく、`REPOS_JSON` が設定されている
- **THEN** `PILOT_AUTOPILOT_DIR` は `${PROJECT_DIR}/.autopilot` に設定される（既存動作、変更なし）

#### Scenario: Worker が AUTOPILOT_DIR を受け取る
- **WHEN** 単一リポジトリで autopilot-launch が Worker を起動する
- **THEN** Worker の `AUTOPILOT_DIR` 環境変数に Pilot の `$AUTOPILOT_DIR` が設定される
