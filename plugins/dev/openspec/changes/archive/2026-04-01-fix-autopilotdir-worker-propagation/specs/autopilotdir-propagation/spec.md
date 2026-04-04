## MODIFIED Requirements

### Requirement: 単一リポジトリ時の PILOT_AUTOPILOT_DIR 明示設定

`resolve_issue_repo_context()` の単一リポジトリ分岐（else）で、`PILOT_AUTOPILOT_DIR` を `${PROJECT_DIR}/.autopilot` として明示設定しなければならない（SHALL）。LLM コンテキスト依存の `$AUTOPILOT_DIR` を参照してはならない。

#### Scenario: 単一リポジトリでの PILOT_AUTOPILOT_DIR 設定
- **WHEN** `repo_id` が `_default` または `REPOS_JSON` が空の場合（単一リポジトリ）
- **THEN** `PILOT_AUTOPILOT_DIR` が `${PROJECT_DIR}/.autopilot` に設定される

#### Scenario: クロスリポジトリでの PILOT_AUTOPILOT_DIR 設定は変更なし
- **WHEN** `repo_id` が `_default` でなく、`REPOS_JSON` が存在する場合（クロスリポジトリ）
- **THEN** `PILOT_AUTOPILOT_DIR` は従来通り `${PROJECT_DIR}/.autopilot` に設定される（既存動作維持）

### Requirement: Worker tmux 環境への AUTOPILOT_DIR 常時注入

`autopilot-launch.md` Step 5 は、`AUTOPILOT_ENV` を常に設定しなければならない（MUST）。`PILOT_AUTOPILOT_DIR` が空の場合は `${PROJECT_DIR}/.autopilot` をフォールバックとして使用する。

#### Scenario: PILOT_AUTOPILOT_DIR 設定済みの場合
- **WHEN** `PILOT_AUTOPILOT_DIR` が非空
- **THEN** `AUTOPILOT_ENV` が `AUTOPILOT_DIR=<PILOT_AUTOPILOT_DIR の値>` に設定される

#### Scenario: PILOT_AUTOPILOT_DIR 未設定の場合のフォールバック
- **WHEN** `PILOT_AUTOPILOT_DIR` が空
- **THEN** `AUTOPILOT_ENV` が `AUTOPILOT_DIR=${PROJECT_DIR}/.autopilot` に設定される

#### Scenario: Worker が AUTOPILOT_DIR を受信する
- **WHEN** Worker の tmux ウィンドウが起動された後
- **THEN** `tmux show-environment -t <window-name>` に `AUTOPILOT_DIR` が含まれる

### Requirement: Worker の IS_AUTOPILOT 正常判定

Worker プロセスが `AUTOPILOT_DIR` を受信した場合、`state-read.sh` が正しい `.autopilot/` ディレクトリの `issue-{N}.json` を参照し、`IS_AUTOPILOT=true` と判定しなければならない（SHALL）。

#### Scenario: Worker が IS_AUTOPILOT=true と判定する
- **WHEN** Worker が `AUTOPILOT_DIR` 環境変数を持ち、該当する `issue-{N}.json` が存在する
- **THEN** Worker の `IS_AUTOPILOT` 判定が `true` になる
