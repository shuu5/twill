## ADDED Requirements

### Requirement: AC deploy E2E トリガー検出

AC 抽出結果から外部アクセスキーワードを検出し、deploy E2E 実行フラグファイルを作成しなければならない（SHALL）。

入力は `${SNAPSHOT_DIR}/01.5-ac-checklist.md`（ac-extract の出力）。出力は `${SNAPSHOT_DIR}/01.6-deploy-e2e-flag`。

キーワードリスト: 外部IP, 外部アクセス, Tailscale, リモートアクセス, CORS, PNA, Private Network Access, deploy E2E, ネットワーク層。

#### Scenario: キーワード検出時にフラグを true に設定
- **WHEN** AC テキストに外部アクセスキーワード（例: "Tailscale", "CORS"）が含まれる
- **THEN** `DEPLOY_E2E_REQUIRED=true` を `01.6-deploy-e2e-flag` に書き込む

#### Scenario: キーワード未検出時にフラグを false に設定
- **WHEN** AC テキストに外部アクセスキーワードが含まれない
- **THEN** `DEPLOY_E2E_REQUIRED=false` を `01.6-deploy-e2e-flag` に書き込む

#### Scenario: AC ファイル不在時のフォールバック
- **WHEN** AC ファイルが存在しない、または ac-extract がスキップされた
- **THEN** `DEPLOY_E2E_REQUIRED=false` を書き込む

### Requirement: 冪等性

フラグファイルが既に存在する場合はスキップしなければならない（MUST）。

#### Scenario: フラグファイル既存時のスキップ
- **WHEN** `${SNAPSHOT_DIR}/01.6-deploy-e2e-flag` が既に存在する
- **THEN** 処理をスキップし既存ファイルを保持する
