## MODIFIED Requirements

### Requirement: handle_chain_subcommand の引数パース拡張

`handle_chain_subcommand()` は `chain_name`（optional）、`--write`、`--check`、`--all` を受け付け、排他制御を実行しなければならない（MUST）。

#### Scenario: 単一 chain の stdout 出力（既存動作の維持）
- **WHEN** `loom chain generate <name>` を実行する
- **THEN** 指定 chain の Template A/B/C を stdout に出力する（既存動作と同一）

#### Scenario: 単一 chain の書き込み（既存動作の維持）
- **WHEN** `loom chain generate <name> --write` を実行する
- **THEN** 指定 chain のテンプレートをファイルに書き込む（既存動作と同一）

#### Scenario: exit code の体系
- **WHEN** いずれかのコマンドバリエーションを実行する
- **THEN** 正常完了/乖離なし → exit 0、乖離あり → exit 1、エラー → exit 1（stderr 出力あり）
