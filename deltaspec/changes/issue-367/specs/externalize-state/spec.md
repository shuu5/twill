## ADDED Requirements

### Requirement: externalize-state コマンド作成

`plugins/twl/commands/externalize-state.md` として atomic コマンドが存在しなければならない（SHALL）。コマンドは SupervisorSession の現在状態を externalization-schema に従って外部ファイルへ書き出さなければならない（SHALL）。

#### Scenario: manual トリガーで実行

- **WHEN** `--trigger manual` でコマンドを実行する
- **THEN** `.autopilot/working-memory.md` に externalization-schema の working-memory.md テンプレートに従ったファイルが書き出される

#### Scenario: wave_complete トリガーで実行

- **WHEN** `--trigger wave_complete` でコマンドを実行する
- **THEN** `.autopilot/wave-{N}-summary.md`（N は session.json の current_wave または "unknown"）に externalization-schema の wave-summary テンプレートに従ったファイルが書き出される

#### Scenario: auto_precompact トリガーで実行

- **WHEN** `--trigger auto_precompact` でコマンドを実行する
- **THEN** `.autopilot/working-memory.md` に書き出され、フロントマターの `trigger` フィールドが `auto_precompact` になる

### Requirement: externalization-schema 参照

externalize-state コマンドは `refs/externalization-schema.md` を参照しなければならない（SHALL）。書き出しファイルのフロントマターと本文構造は externalization-schema に定義されたテンプレートに準拠しなければならない（MUST）。

#### Scenario: externalization-schema に準拠したファイル生成

- **WHEN** externalize-state を実行する
- **THEN** 書き出されたファイルのフロントマターに `externalized_at`・`trigger`・`lifecycle` フィールドが含まれる

### Requirement: ExternalizationRecord の追記

コマンドは実行後に ExternalizationRecord を `.autopilot/session.json` の `externalization_log` 配列に追記しなければならない（SHALL）。

#### Scenario: session.json への記録

- **WHEN** externalize-state が正常に実行された場合
- **THEN** `.autopilot/session.json` の `externalization_log` に `externalized_at`・`trigger`・`output_path` を含むレコードが追加される

### Requirement: deps.yaml への登録

`plugins/twl/deps.yaml` に externalize-state エントリが追加されなければならない（SHALL）。su-compact は externalize-state を `calls` 依存として参照しなければならない（MUST）。

#### Scenario: deps.yaml 整合性チェック通過

- **WHEN** `twl check` を実行する
- **THEN** externalize-state の deps.yaml エントリに関するエラーが発生しない
