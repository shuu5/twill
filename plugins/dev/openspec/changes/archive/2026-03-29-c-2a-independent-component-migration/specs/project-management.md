## ADDED Requirements

### Requirement: Project管理系コンポーネント移植

既存 dev plugin から Project 管理系コンポーネント8個を loom-plugin-dev に移植しなければならない（SHALL）。

対象コンポーネント:
- project-create: プロジェクト新規作成（bare repo + worktree + テンプレート + OpenSpec）
- project-governance: ガバナンス適用（Hooks + スキーマscaffold + CLAUDE.md拡張）
- project-migrate: 既存プロジェクトの最新テンプレート移行
- container-dependency-check: テンプレートのコンテナ依存と container-manager の実状態照合
- setup-crg: code-review-graph MCP セットアップ
- snapshot-analyze: プロジェクト分析（ファイルスキャン、スタック自動検出）
- snapshot-classify: AI Tier 分類 + ユーザー確認テーブル表示
- snapshot-generate: manifest.yaml + テンプレートファイル生成

#### Scenario: Project管理系の deps.yaml 登録
- **WHEN** 8個全てのコンポーネントが移植された
- **THEN** deps.yaml の commands セクションに全8個が type: atomic で定義されている

#### Scenario: Project管理系の spawnable_by 設定
- **WHEN** project-create, project-governance, project-migrate が deps.yaml に定義された
- **THEN** spawnable_by に controller が含まれている（co-project から呼ばれるため）

#### Scenario: Project管理系のファイル配置
- **WHEN** 各コンポーネントのプロンプトファイルが作成された
- **THEN** commands/<name>.md の形式で配置されている
