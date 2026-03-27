## MODIFIED Requirements

### Requirement: validate の JSON 出力

`--validate --format json` 実行時、validate_types, validate_body_refs, validate_v3_schema, chain_validate の結果を items 配列として JSON 出力しなければならない（SHALL）。各 item は severity, component, message に加え code フィールドを含む。

#### Scenario: validate violations の JSON 出力
- **WHEN** 型ルール違反がある状態で `--validate --format json` を実行する
- **THEN** items に `{"severity": "critical", "component": "...", "message": "...", "code": "type-rule-violation"}` 形式の要素が含まれる

#### Scenario: validate 正常時の JSON 出力
- **WHEN** 全型ルールが満たされた状態で `--validate --format json` を実行する
- **THEN** items が空配列で、summary.total が 0、exit_code が 0 となる

#### Scenario: chain_validate の結果統合
- **WHEN** chain 検証で warning がある状態で `--validate --format json` を実行する
- **THEN** items に chain 由来の warning も含まれる

### Requirement: deep-validate の JSON 出力

`--deep-validate --format json` 実行時、criticals/warnings/infos の3リストを severity にマッピングして items 配列として JSON 出力しなければならない（MUST）。各 item は severity, component, message に加え check フィールドを含む。

#### Scenario: deep-validate の JSON 出力
- **WHEN** controller bloat 警告がある状態で `--deep-validate --format json` を実行する
- **THEN** items に `{"severity": "warning", "component": "...", "message": "...", "check": "A"}` 形式の要素が含まれる

#### Scenario: deep-validate criticals の JSON 出力
- **WHEN** critical な深層違反がある状態で `--deep-validate --format json` を実行する
- **THEN** items に severity: critical の要素が含まれ、exit_code が 1 となる

### Requirement: check の JSON 出力

`--check --format json` 実行時、check_files の結果と chain_validate の結果を items 配列として JSON 出力しなければならない（SHALL）。各 item は severity, component, message に加え path, status フィールドを含む。

#### Scenario: check の正常系 JSON 出力
- **WHEN** 全ファイルが存在する状態で `--check --format json` を実行する
- **THEN** items に `{"severity": "ok", "component": "...", "message": "File exists", "path": "...", "status": "ok"}` 形式の要素が含まれる

#### Scenario: check の missing ファイル JSON 出力
- **WHEN** ファイルが欠損している状態で `--check --format json` を実行する
- **THEN** items に `{"severity": "critical", "component": "...", "message": "...", "path": "...", "status": "missing"}` 形式の要素が含まれ、exit_code が 1 となる

#### Scenario: check で chain_validate の結果統合
- **WHEN** v3.0 deps.yaml で chain 違反がある状態で `--check --format json` を実行する
- **THEN** items にファイル存在チェック結果と chain 検証結果の両方が含まれる
