## MODIFIED Requirements

### Requirement: audit のデータ収集関数分離

audit_report() から print() を分離し、データ収集関数 audit_collect() を新設しなければならない（MUST）。audit_collect() は items リストを return し、audit_report() は audit_collect() を呼んでテキスト出力するラッパーとなる。

#### Scenario: audit_collect の戻り値
- **WHEN** audit_collect() を呼び出す
- **THEN** items リストが返され、各要素が severity, component, message, section, value, threshold フィールドを持つ

#### Scenario: audit_report の後方互換
- **WHEN** 既存の `--audit` を `--format` なしで実行する
- **THEN** 出力が変更前と完全に同一である

### Requirement: audit の JSON 出力

`--audit --format json` 実行時、audit_collect() の結果を共通エンベロープで JSON 出力しなければならない（SHALL）。

#### Scenario: audit の JSON 出力
- **WHEN** controller サイズ警告がある状態で `--audit --format json` を実行する
- **THEN** items に `{"severity": "warning", "component": "...", "message": "...", "section": "controller_size", "value": 186, "threshold": 120}` 形式の要素が含まれる

### Requirement: complexity のデータ収集関数分離

complexity_report() から print() を分離し、データ収集関数 complexity_collect() を新設しなければならない（MUST）。complexity_collect() は items リストを return し、complexity_report() は complexity_collect() を呼んでテキスト出力するラッパーとなる。

#### Scenario: complexity_collect の戻り値
- **WHEN** complexity_collect() を呼び出す
- **THEN** items リストが返され、各要素が severity, component, message, metric フィールドを持つ

#### Scenario: complexity_report の後方互換
- **WHEN** 既存の `--complexity` を `--format` なしで実行する
- **THEN** 出力が変更前と完全に同一である

### Requirement: complexity の JSON 出力

`--complexity --format json` 実行時、complexity_collect() の結果を共通エンベロープで JSON 出力しなければならない（SHALL）。

#### Scenario: complexity の JSON 出力
- **WHEN** fan-out 閾値超過がある状態で `--complexity --format json` を実行する
- **THEN** items に `{"severity": "warning", "component": "...", "message": "...", "metric": "fan_out", "value": 9, "threshold": 8}` 形式の要素が含まれる
