## Requirements

### Requirement: --format json 引数

twl CLI に `--format` 引数を追加し、値 `json` を受け付けなければならない（SHALL）。未指定時は既存のテキスト出力を維持する。

#### Scenario: --format json 指定時
- **WHEN** `--validate --format json` を実行する
- **THEN** stdout に純粋な JSON のみが出力される

#### Scenario: --format 未指定時
- **WHEN** `--validate` を実行する（--format なし）
- **THEN** 既存のテキスト出力がそのまま表示される

#### Scenario: 不正な format 値
- **WHEN** `--format xml` を実行する
- **THEN** argparse がエラーを返す

### Requirement: 共通エンベロープ構造

JSON 出力は共通エンベロープで統一されなければならない（MUST）。エンベロープは command, version, plugin, items, summary, exit_code の6フィールドを含む。

#### Scenario: エンベロープフィールド検証
- **WHEN** 任意のコマンドを `--format json` で実行する
- **THEN** 出力 JSON が `command`（文字列）, `version`（文字列）, `plugin`（文字列）, `items`（配列）, `summary`（オブジェクト）, `exit_code`（整数）を全て含む

#### Scenario: summary 集計
- **WHEN** items に severity: critical が2件、warning が1件ある
- **THEN** summary は `{"critical": 2, "warning": 1, "info": 0, "ok": 0, "total": 3}` となる

### Requirement: items 共通フィールド

items 配列の各要素は severity, component, message の3フィールドを含まなければならない（SHALL）。

#### Scenario: items 共通フィールド存在確認
- **WHEN** JSON 出力の items 配列の各要素を検査する
- **THEN** 全要素が `severity`（"critical"|"warning"|"info"|"ok"のいずれか）, `component`（文字列）, `message`（文字列）を持つ

### Requirement: exit code の一貫性

JSON 出力時もテキスト出力時と同一の exit code を返さなければならない（MUST）。violations/criticals があれば exit 1、なければ exit 0。

#### Scenario: JSON 出力時の exit code
- **WHEN** violations ありの `--validate --format json` を実行する
- **THEN** exit code が 1 であり、かつ JSON 内の exit_code フィールドも 1 である

#### Scenario: 正常時の exit code
- **WHEN** violations なしの `--validate --format json` を実行する
- **THEN** exit code が 0 であり、かつ JSON 内の exit_code フィールドも 0 である
