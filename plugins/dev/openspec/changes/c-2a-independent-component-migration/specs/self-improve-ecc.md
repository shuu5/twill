## ADDED Requirements

### Requirement: Self-improve/ECC系コンポーネント移植

既存 dev plugin から Self-improve/ECC 系コンポーネント4個を loom-plugin-dev に移植しなければならない（SHALL）。

対象コンポーネント:
- self-improve-collect: self-improve Issue の収集・分類・関連コンポーネント特定
- self-improve-propose: ECC 知識照合を含む改善提案生成
- self-improve-close: self-improve Issue のクローズ処理（PR マージ → コメント追加 → Issue クローズ）
- ecc-monitor: ECC リポジトリの変更検知・関連性評価

#### Scenario: Self-improve/ECC系の deps.yaml 登録
- **WHEN** 4個全てのコンポーネントが移植された
- **THEN** deps.yaml の commands セクションに全4個が type: atomic で定義されている

#### Scenario: Self-improve/ECC系の spawnable_by 設定
- **WHEN** 全4個が deps.yaml に定義された
- **THEN** spawnable_by に controller が含まれている（co-autopilot の self-improve フローから呼ばれるため）

#### Scenario: Self-improve/ECC系のファイル配置
- **WHEN** 各コンポーネントのプロンプトファイルが作成された
- **THEN** commands/<name>/COMMAND.md の形式で配置されている
