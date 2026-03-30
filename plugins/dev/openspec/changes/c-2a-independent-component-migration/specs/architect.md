## ADDED Requirements

### Requirement: Architect系コンポーネント移植

既存 dev plugin から Architect 系コンポーネント5個を loom-plugin-dev に移植しなければならない（SHALL）。

対象コンポーネント:
- architect-completeness-check: アーキテクチャ完全性チェック
- architect-decompose: contexts/ + phases/ → Issue候補リスト分解 + 整合性チェック
- architect-group-refine: スケルトンIssueグループの一括精緻化
- architect-issue-create: Issue候補リストから GitHub Issue 一括作成
- evaluate-architecture: 設計のアーキテクチャパターン評価

#### Scenario: Architect系の deps.yaml 登録
- **WHEN** 5個全てのコンポーネントが移植された
- **THEN** deps.yaml の commands セクションに全5個が type: atomic で定義されている

#### Scenario: Architect系の spawnable_by 設定
- **WHEN** 全5個が deps.yaml に定義された
- **THEN** spawnable_by に controller が含まれている（co-architect から呼ばれるため）

#### Scenario: Architect系のファイル配置
- **WHEN** 各コンポーネントのプロンプトファイルが作成された
- **THEN** commands/<name>.md の形式で配置されている
