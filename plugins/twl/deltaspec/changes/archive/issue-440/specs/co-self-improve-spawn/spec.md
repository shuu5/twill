## MODIFIED Requirements

### Requirement: co-self-improve の spawn 受取手順

co-self-improve SKILL.md は su-observer から spawn される場合の情報受取手順を冒頭に記載しなければならない（SHALL）。spawn 時プロンプトから対象 session、タスク内容、観察モードを受け取り、以降の動作に反映しなければならない（SHALL）。

#### Scenario: su-observer からの spawn 受信
- **WHEN** su-observer が `cld-spawn` を使って co-self-improve を起動する
- **THEN** co-self-improve は spawn 時プロンプトから「対象 session 情報」「タスク内容」「観察モード」を解釈し、適切な内部フロー（scenario-run / retrospect / test-project-manage）に進まなければならない（SHALL）

#### Scenario: Skill() 直接呼出し記述の削除
- **WHEN** co-self-improve SKILL.md を参照する
- **THEN** `Skill(twl:co-self-improve)` による直接呼出しに依存した記述が存在してはならない（SHALL NOT）

### Requirement: deps.yaml の su-observer.supervises 更新

deps.yaml の su-observer.supervises フィールドに co-self-improve が含まれていなければならない（SHALL）。

#### Scenario: deps.yaml の整合性確認
- **WHEN** `twl check` で deps.yaml を検証する
- **THEN** su-observer.supervises に co-self-improve が含まれており、co-self-improve.spawnable_by に su-observer が含まれているという非対称性が解消されていなければならない（SHALL）
