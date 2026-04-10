## ADDED Requirements

### Requirement: wave-collect コマンド作成

Wave 完了時に co-autopilot の実行結果を収集する atomic コマンド `wave-collect` を作成しなければならない（SHALL）。コマンドは `plugins/twl/commands/wave-collect.md` に配置される。

#### Scenario: Wave サマリ生成
- **WHEN** Wave 番号 N を引数に `wave-collect` が呼び出される
- **THEN** `.autopilot/issues/issue-*.json` から全 Issue の結果を読み込み、`.supervisor/wave-{N}-summary.md` にサマリを出力する

### Requirement: 構造化出力フォーマット

Wave サマリは構造化 Markdown 形式で出力しなければならない（SHALL）。出力先パスは `.supervisor/wave-{N}-summary.md` でなければならない（MUST）。

#### Scenario: サマリフォーマット検証
- **WHEN** wave-collect が正常完了する
- **THEN** 出力ファイルに「概要統計（total/done/failed）」「Issue 一覧表（番号/ステータス/PR/介入回数）」「介入パターン統計」の各セクションが含まれる

#### Scenario: 出力ディレクトリ未作成
- **WHEN** `.supervisor/` ディレクトリが存在しない状態で wave-collect が呼び出される
- **THEN** `.supervisor/` を自動作成してからファイルを出力する

### Requirement: deps.yaml エントリ追加

`plugins/twl/deps.yaml` に `wave-collect` エントリを追加しなければならない（SHALL）。type は `atomic` でなければならない（MUST）。

#### Scenario: deps.yaml エントリ検証
- **WHEN** `twl check` を実行する
- **THEN** wave-collect エントリが valid と判定される

### Requirement: 介入パターン統計計算

介入回数の集計と頻出パターンを計算しなければならない（SHALL）。

#### Scenario: 介入統計
- **WHEN** Wave 内に介入 (retry_count > 0) した Issue が存在する
- **THEN** サマリに「介入率（介入 Issue 数 / 全 Issue 数）」と「平均介入回数」が記録される
