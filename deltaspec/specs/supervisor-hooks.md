## Requirements

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

### Requirement: テスト群の期待値更新

`_no_autopilot_dir` を含む既存テストは「AUTOPILOT_DIR 未設定 + git 内 → イベント生成」に期待値を変更しなければならない（SHALL）。

#### Scenario: _no_autopilot_dir テストの期待値変更

- **WHEN** `AUTOPILOT_DIR` 未設定の git リポジトリ内環境でテストを実行する
- **THEN** テストはイベントファイルが生成されることを期待しなければならない（MUST）


### Requirement: SESSION_ID サニタイズ（SU-9）

supervisor hook 5 本（heartbeat, input-wait, input-clear, skill-step, session-end）は SESSION_ID をファイル名に埋め込む直前に allow-list サニタイズ（`[A-Za-z0-9_-]`）を適用しなければならない（SHALL）。

サニタイズ後に SESSION_ID が空文字となった場合は `$$`（プロセス ID）にフォールバックしなければならない（SHALL）。

#### Scenario: path-traversal 文字を含む SESSION_ID

- **WHEN** SESSION_ID が `../../etc/passwd` のような path-traversal 文字を含む値で hook が呼び出される
- **THEN** SESSION_ID はサニタイズされ、安全なファイル名部分のみが使用されなければならない（MUST）

#### Scenario: 通常の UUID 形式の SESSION_ID

- **WHEN** SESSION_ID が `550e8400-e29b-41d4-a716-446655440000` 形式の UUID で hook が呼び出される
- **THEN** UUID のハイフンは許可文字のため SESSION_ID はそのまま使用されなければならない（SHALL）

#### Scenario: SESSION_ID が空になった場合のフォールバック

- **WHEN** SESSION_ID がサニタイズ後に空文字になる
- **THEN** SESSION_ID には `$$`（プロセス ID）が使用されなければならない（SHALL）

### Requirement: サニタイズ警告出力

supervisor hook はサニタイズで SESSION_ID の値が変化した場合に限り、警告行を stderr に出力しなければならない（SHALL）。

警告行は raw SESSION_ID の値を含んではならない（MUST NOT）。

#### Scenario: サニタイズで値が変化した場合の警告

- **WHEN** SESSION_ID にサニタイズ対象文字が含まれ、サニタイズ後の値が元の値と異なる
- **THEN** `[supervisor-hook][warn] SESSION_ID sanitized (hook=<name> pid=<pid>)` が stderr に出力されなければならない（MUST）

#### Scenario: サニタイズで値が変化しない場合は警告なし

- **WHEN** SESSION_ID が allow-list 文字のみで構成される
- **THEN** stderr に何も出力されてはならない（MUST NOT）
