## ADDED Requirements

### Requirement: TaskCreate による Phase 進捗登録

autopilot の各 Phase 開始時に TaskCreate ツールで Phase タスクを登録しなければならない（SHALL）。

#### Scenario: Phase 開始時のタスク登録
- **WHEN** Phase 1 が開始され、対象 Issue が #42, #43, #44 である
- **THEN** TaskCreate で `Phase 1: Issue #42, #43, #44` のタスクが status=in_progress で登録される

#### Scenario: 単一 Issue の Phase
- **WHEN** Phase 2 が開始され、対象 Issue が #45 のみである
- **THEN** TaskCreate で `Phase 2: Issue #45` のタスクが status=in_progress で登録される

### Requirement: TaskUpdate による Issue 完了追跡

Issue の状態が `done` または `failed` に遷移した時点で TaskUpdate を実行しなければならない（MUST）。

#### Scenario: Issue 正常完了
- **WHEN** issue-42.json の status が `done` に遷移する
- **THEN** 対応する Phase タスクの説明に `#42: done` が追記される

#### Scenario: Issue 失敗
- **WHEN** issue-42.json の status が `failed` に確定する（リトライ上限到達）
- **THEN** 対応する Phase タスクの説明に `#42: failed` が追記される

#### Scenario: Phase 全 Issue 完了
- **WHEN** Phase 内の全 Issue が `done` または `failed (確定)` に遷移する
- **THEN** Phase タスクの status が `completed` に更新される

### Requirement: specialist 内部での TaskCreate 不使用

specialist コンポーネントおよび atomic コマンドの内部処理では TaskCreate/TaskUpdate を使用してはならない（MUST）。

#### Scenario: specialist 実行中
- **WHEN** merge-gate 内で specialist（code-reviewer 等）が実行される
- **THEN** specialist は TaskCreate/TaskUpdate を呼び出さない（短命タスクのオーバーヘッド回避）

## REMOVED Requirements

### Requirement: --auto/--auto-merge フラグの廃止

旧プラグインの `--auto` および `--auto-merge` フラグを廃止しなければならない（MUST）。全操作は co-autopilot 経由で実行され、フラグによる分岐は存在しない。

#### Scenario: フラグ不在の確認
- **WHEN** co-autopilot の SKILL.md および全 workflow/atomic コンポーネントを検索する
- **THEN** `--auto` および `--auto-merge` フラグへの参照が存在しない

### Requirement: DEV_AUTOPILOT_SESSION 環境変数の廃止

旧プラグインの `DEV_AUTOPILOT_SESSION` 環境変数を廃止しなければならない（MUST）。セッション状態は session.json で管理され、環境変数に依存しない。

#### Scenario: 環境変数不在の確認
- **WHEN** 全スクリプトおよび SKILL.md を検索する
- **THEN** `DEV_AUTOPILOT_SESSION` への参照が存在しない
