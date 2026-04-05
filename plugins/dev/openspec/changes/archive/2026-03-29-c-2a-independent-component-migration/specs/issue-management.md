## ADDED Requirements

### Requirement: Issue管理系コンポーネント移植

既存 dev plugin から Issue 管理系コンポーネント7個を loom-plugin-dev に移植しなければならない（SHALL）。

対象コンポーネント:
- issue-dig: Per-Issue 曖昧点検出（AC検証可能性、スコープ境界、依存関係、実装粒度）
- issue-structure: Issue内容の構造化（タイプ判定+テンプレート読込+フィールド埋め）
- issue-create: GitHub Issue 作成
- issue-bulk-create: 親Issue+子Issue群の一括起票
- issue-tech-debt-absorb: tech-debt Issue の吸収提案
- project-board-sync: Issue作成後に Project V2 へ自動追加
- issue-assess: Issue品質評価

#### Scenario: Issue管理系の deps.yaml 登録
- **WHEN** 7個全てのコンポーネントが移植された
- **THEN** deps.yaml の commands セクションに全7個が type: atomic で定義されている

#### Scenario: Issue管理系の spawnable_by 設定
- **WHEN** issue-dig, issue-structure, issue-create が deps.yaml に定義された
- **THEN** spawnable_by に controller が含まれている（co-issue から呼ばれるため）

#### Scenario: Issue管理系のファイル配置
- **WHEN** 各コンポーネントのプロンプトファイルが作成された
- **THEN** commands/<name>.md の形式で配置されている

### Requirement: issue-create の参照更新

issue-create の body 内で参照する Issue テンプレートは refs/ 配下の ref-issue-template-bug, ref-issue-template-feature を使用しなければならない（MUST）。

#### Scenario: テンプレート参照の整合性
- **WHEN** issue-create の COMMAND.md が作成された
- **THEN** body 内の Issue テンプレート参照が ref-issue-template-bug, ref-issue-template-feature を指している
