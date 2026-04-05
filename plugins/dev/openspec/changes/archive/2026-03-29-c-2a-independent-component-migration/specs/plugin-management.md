## ADDED Requirements

### Requirement: Plugin管理系コンポーネント移植

既存 dev plugin から Plugin 管理系コンポーネント10個を loom-plugin-dev に移植しなければならない（SHALL）。

対象コンポーネント（atomic 8個）:
- plugin-interview: プラグイン作成のためのユーザー要件インタビュー
- plugin-research: プラグイン設計情報を Web 取得し構造化サマリー作成
- plugin-design: 型マッピング + deps.yaml 設計
- plugin-generate: プラグインファイル一式生成
- plugin-migrate-analyze: 既存プラグインの AT 移行分析
- plugin-diagnose: プラグインの問題診断（構造+5原則チェック）
- plugin-fix: 診断結果に基づくコンポーネント修正適用
- plugin-verify: 統合検証+5原則チェック

対象コンポーネント（composite 2個）:
- plugin-phase-diagnose: 並列診断フェーズ（specialist x3 並列 spawn + 統合処理）
- plugin-phase-verify: 並列検証フェーズ（specialist x3 並列 spawn + 統合処理）

#### Scenario: Plugin管理系の deps.yaml 登録
- **WHEN** 10個全てのコンポーネントが移植された
- **THEN** atomic 8個は type: atomic、composite 2個は type: composite で deps.yaml に定義されている

#### Scenario: Plugin管理系の spawnable_by 設定
- **WHEN** 全10個が deps.yaml に定義された
- **THEN** spawnable_by に controller が含まれている（co-project 経由で呼ばれるため）

#### Scenario: composite の can_spawn 設定
- **WHEN** plugin-phase-diagnose, plugin-phase-verify が deps.yaml に定義された
- **THEN** can_spawn に specialist が含まれている

#### Scenario: Plugin管理系のファイル配置
- **WHEN** 各コンポーネントのプロンプトファイルが作成された
- **THEN** commands/<name>.md の形式で配置されている
