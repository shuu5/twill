## ADDED Requirements

### Requirement: テストフェーズ統合

サービスヘルスチェック、E2E 品質ゲート、テスト実行を統合したフェーズとして機能しなければならない（SHALL）。

chain 外のスタンドアロンコマンドとして配置し、手動テスト実行やデバッグ用途で独立利用可能とする。

#### Scenario: サービスヘルスチェック成功後のテスト実行
- **WHEN** services.yaml が存在し required サービスが全て起動済み
- **THEN** E2E 品質ゲートを実行し、PASS 後にテスト実行へ進む

#### Scenario: サービス未起動時の自動起動
- **WHEN** services.yaml が存在し required サービスが未起動
- **THEN** サービス起動を自動実行し、ヘルスチェック成功後にテスト実行へ進む

#### Scenario: services.yaml 不在時のスキップ
- **WHEN** services.yaml が存在しない
- **THEN** サービスヘルスチェックをスキップしテスト実行へ直接進む

### Requirement: deploy E2E フラグ連携

SNAPSHOT_DIR から deploy E2E フラグを読み取り、deploy E2E の必要性を判定しなければならない（MUST）。

#### Scenario: deploy E2E 有効時の追加実行
- **WHEN** `DEPLOY_E2E_REQUIRED=true` がフラグファイルに設定されている
- **THEN** テスト実行に deploy E2E プロジェクトを追加する

#### Scenario: deploy E2E 無効時の通常実行
- **WHEN** `DEPLOY_E2E_REQUIRED=false` またはフラグファイルが不在
- **THEN** 通常のテスト実行のみ行う

### Requirement: specialist 呼び出し制約

specialist は Task tool で呼び出さなければならない（MUST）。Skill tool での specialist 呼び出しは禁止する。

#### Scenario: E2E 品質ゲートの Task 呼び出し
- **WHEN** E2E テストを含むテスト実行が必要
- **THEN** `Task(subagent_type="twl:e2e-quality")` で E2E 品質ゲートを実行する
