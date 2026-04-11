## MODIFIED Requirements

### Requirement: bare sibling 優先解決

`_autopilot_dir()` の fallback は env var → bare sibling → main worktree 配下 → first real worktree → cwd の順で試さなければならない（SHALL）。bare sibling とは main worktree path の親ディレクトリに `.autopilot/` が存在する場合（`Path(<main_wt>).parent / ".autopilot"`）を指す。

#### Scenario: bare sibling が存在するとき

- **WHEN** `AUTOPILOT_DIR` 未設定、かつ `git worktree list` で main worktree が `twill/main/` と判定され、`twill/.autopilot/` が存在する
- **THEN** `_autopilot_dir()` は `twill/.autopilot/` を返さなければならない（SHALL）

#### Scenario: bare sibling が存在せず main worktree 配下が存在するとき

- **WHEN** `AUTOPILOT_DIR` 未設定、かつ `twill/.autopilot/` が存在せず `twill/main/.autopilot/` が存在する
- **THEN** `_autopilot_dir()` は `twill/main/.autopilot/` を返さなければならない（SHALL）

#### Scenario: env var が設定されているとき

- **WHEN** `AUTOPILOT_DIR=/custom/path` が設定されている
- **THEN** `_autopilot_dir()` は常に `/custom/path` を返さなければならない（SHALL、既存動作維持）

### Requirement: エラーメッセージに試行パスと AUTOPILOT_DIR 案内を含める

ファイル不在時の `StateError` メッセージは、実際に試したパス一覧と `AUTOPILOT_DIR` export 方法を含まなければならない（SHALL）。

#### Scenario: state file が見つからないとき

- **WHEN** `python3 -m twl.autopilot.state read --type issue --issue 443` を実行し、対象ファイルが存在しない
- **THEN** エラーメッセージに「試したパス」と「`export AUTOPILOT_DIR=<path>`」の文字列が含まれなければならない（SHALL）

## MODIFIED Requirements

### Requirement: Pilot が `pr` フィールドを書き込み可能

`_PILOT_ISSUE_ALLOWED_KEYS` に `"pr"` を追加し、Pilot role が issue-{N}.json の `pr` フィールドを更新できなければならない（SHALL）。

#### Scenario: Pilot が pr フィールドを設定するとき

- **WHEN** `python3 -m twl.autopilot.state write --role pilot --type issue --issue N --set "pr=467"` を実行する
- **THEN** `StateError` を raise せずに正常終了しなければならない（SHALL）

#### Scenario: Pilot が許可されていないフィールドを設定しようとするとき

- **WHEN** `python3 -m twl.autopilot.state write --role pilot --type issue --issue N --set "current_step=foo"` を実行する
- **THEN** `StateError` を raise しなければならない（SHALL、既存動作維持）

## ADDED Requirements

### Requirement: orchestrator.sh が AUTOPILOT_DIR 未設定時に警告する

`autopilot-orchestrator.sh` は起動時に `AUTOPILOT_DIR` が空の場合、stderr に警告を出力しなければならない（SHALL）。

#### Scenario: AUTOPILOT_DIR 未設定で orchestrator が起動するとき

- **WHEN** `AUTOPILOT_DIR` 未設定のまま `autopilot-orchestrator.sh` を起動する
- **THEN** stderr に `WARN: AUTOPILOT_DIR` を含む警告メッセージが出力されなければならない（SHALL）
