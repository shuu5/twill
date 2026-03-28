## ADDED Requirements

### Requirement: Dead Component/Triage系コンポーネント移植

既存 dev plugin から Dead Component/Triage 系コンポーネント5個を loom-plugin-dev に移植しなければならない（SHALL）。

対象コンポーネント（atomic 3個）:
- dead-component-detect: Dead Component 検出・情報収集・一覧テーブル表示
- dead-component-execute: 選択された Dead Component の削除実行・整合性検証
- triage-execute: 分類済み tech-debt Issue の一括処理

対象コンポーネント（workflow 2個）:
- workflow-dead-cleanup: Dead Component 検出結果に基づく確認付き削除ワークフロー
- workflow-tech-debt-triage: tech-debt Issue の棚卸しワークフロー

#### Scenario: workflow の section 配置
- **WHEN** workflow-dead-cleanup, workflow-tech-debt-triage が移植された
- **THEN** skills/<name>/SKILL.md として配置されている（commands/ ではない）

#### Scenario: atomic の section 配置
- **WHEN** dead-component-detect, dead-component-execute, triage-execute が移植された
- **THEN** commands/<name>/COMMAND.md として配置されている

#### Scenario: Dead Component/Triage系の deps.yaml 登録
- **WHEN** 5個全てのコンポーネントが移植された
- **THEN** atomic 3個は commands セクション、workflow 2個は skills セクションに定義されている

#### Scenario: workflow の spawnable_by 設定
- **WHEN** workflow-dead-cleanup, workflow-tech-debt-triage が deps.yaml に定義された
- **THEN** spawnable_by に controller が含まれ、can_spawn に atomic が含まれている
