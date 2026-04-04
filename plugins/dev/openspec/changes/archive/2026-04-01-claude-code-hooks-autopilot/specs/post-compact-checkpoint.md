## ADDED Requirements

### Requirement: PostCompact チェックポイント保存

compaction 発生後に autopilot 進捗状態のタイムスタンプを保存しなければならない（SHALL）。

#### Scenario: autopilot 配下での compaction
- **WHEN** PostCompact hook が発火し、環境変数 `AUTOPILOT_DIR` が設定されている
- **THEN** state-write.sh で `last_compact_at` に ISO 8601 タイムスタンプを記録しなければならない（MUST）

#### Scenario: 通常セッションでの compaction
- **WHEN** PostCompact hook が発火し、環境変数 `AUTOPILOT_DIR` が未設定
- **THEN** hook スクリプトは何も実行せず exit 0 で終了する（SHALL）

#### Scenario: state-write 失敗時
- **WHEN** state-write.sh がエラーを返す
- **THEN** hook スクリプトはエラーを無視し exit 0 で終了する（SHALL）。Worker の実行を中断してはならない（MUST NOT）

#### Scenario: hooks.json への登録
- **WHEN** hooks/hooks.json を読み込む
- **THEN** PostCompact セクションにエントリが存在しなければならない（MUST）
