## ADDED Requirements

### Requirement: PermissionRequest 自動承認

autopilot Worker の permission ダイアログを自動承認し、ヘッドレス実行を維持しなければならない（SHALL）。

#### Scenario: autopilot 配下での permission 要求
- **WHEN** PermissionRequest hook が発火し、環境変数 `AUTOPILOT_DIR` が設定されている
- **THEN** hook スクリプトが `"allow"` を返し、permission ダイアログをスキップしなければならない（MUST）

#### Scenario: 通常セッションでの permission 要求
- **WHEN** PermissionRequest hook が発火し、環境変数 `AUTOPILOT_DIR` が未設定
- **THEN** hook スクリプトは JSON を出力せず exit 0 で終了する（SHALL）。通常の permission フローに影響を与えてはならない（MUST NOT）

#### Scenario: hooks.json への登録
- **WHEN** hooks/hooks.json を読み込む
- **THEN** PermissionRequest セクションにエントリが存在しなければならない（MUST）
