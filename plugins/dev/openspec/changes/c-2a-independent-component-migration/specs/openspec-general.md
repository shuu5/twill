## ADDED Requirements

### Requirement: OpenSpec/汎用系コンポーネント移植

既存 dev plugin から OpenSpec/汎用系コンポーネント5個を loom-plugin-dev に移植しなければならない（SHALL）。opsx-propose は既存のため対象外。

対象コンポーネント:
- explore: アイデア検討・問題調査・要件整理のための思考パートナー
- propose: change ディレクトリを作成し全 artifact を一括生成
- apply: OpenSpec change の tasks.md に沿ってタスクを実装
- archive: 完了済み change を archive/ に移動
- check: ワークフロー準備状況チェック

#### Scenario: section 誤配置の修正
- **WHEN** explore, propose, apply, archive が移植された
- **THEN** commands/<name>/COMMAND.md として配置されている（skills/ ではない）

#### Scenario: OpenSpec/汎用系の deps.yaml 登録
- **WHEN** 5個全てのコンポーネントが移植された
- **THEN** deps.yaml の commands セクションに全5個が type: atomic で定義されている

#### Scenario: explore の spawnable_by 設定
- **WHEN** explore が deps.yaml に定義された
- **THEN** spawnable_by に controller と workflow の両方が含まれている（co-issue, co-architect, workflow-setup から呼ばれるため）

#### Scenario: propose/apply/archive の spawnable_by 設定
- **WHEN** propose, apply, archive が deps.yaml に定義された
- **THEN** spawnable_by に controller と workflow が含まれている
