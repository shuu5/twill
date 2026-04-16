## MODIFIED Requirements

### Requirement: EVENTS_DIR 解決を git-common-dir ベースに変更

全 5 supervisor hook の EVENTS_DIR 解決ロジックを `AUTOPILOT_DIR` ベースから `git rev-parse --git-common-dir` ベースに変更しなければならない（SHALL）。

解決式: `EVENTS_DIR="${GIT_COMMON_DIR}/../main/.supervisor/events"` とする（SHALL）。

#### Scenario: 非 autopilot セッションでのイベント生成

- **WHEN** `AUTOPILOT_DIR` が未設定の co-explore / co-issue セッション内で AskUserQuestion が発火する
- **THEN** `main/.supervisor/events/input-wait-<session_id>` ファイルが生成されなければならない（MUST）

#### Scenario: autopilot Worker セッションでの後方互換

- **WHEN** `AUTOPILOT_DIR` が設定済みの autopilot Worker セッションで AskUserQuestion が発火する
- **THEN** `main/.supervisor/events/input-wait-<session_id>` ファイルが生成されなければならない（MUST）

#### Scenario: git 外セッションでの静的終了

- **WHEN** git リポジトリ外のセッションで supervisor hook が呼び出される
- **THEN** hook は何も出力せず exit 0 で終了しなければならない（SHALL）

### Requirement: AUTOPILOT_DIR ゲートの撤去

全 5 supervisor hook から `AUTOPILOT_DIR` 未設定時の早期 exit ゲートを撤去しなければならない（SHALL）。

`git rev-parse --git-common-dir` の成功（空でない文字列が返る）を唯一のゲート条件としなければならない（SHALL）。

#### Scenario: AUTOPILOT_DIR 未設定 + git 内セッション

- **WHEN** `AUTOPILOT_DIR` が設定されていないが git リポジトリ内のセッションで heartbeat hook が呼び出される
- **THEN** hook は `EVENTS_DIR` を `git rev-parse --git-common-dir` から解決し、イベントファイルを生成しなければならない（MUST）

#### Scenario: AUTOPILOT_DIR 未設定 + git 外セッション

- **WHEN** `AUTOPILOT_DIR` が設定されておらず git リポジトリ外のセッションで hook が呼び出される
- **THEN** hook は exit 0 で静かに終了しなければならない（SHALL）

## MODIFIED Requirements

### Requirement: テスト群の期待値更新

`_no_autopilot_dir` を含む既存テストは「AUTOPILOT_DIR 未設定 + git 内 → イベント生成」に期待値を変更しなければならない（SHALL）。

#### Scenario: _no_autopilot_dir テストの期待値変更

- **WHEN** `AUTOPILOT_DIR` 未設定の git リポジトリ内環境でテストを実行する
- **THEN** テストはイベントファイルが生成されることを期待しなければならない（MUST）
