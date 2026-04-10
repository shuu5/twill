## ADDED Requirements

### Requirement: specialist 出力スキーマキーワード検証

deep-validate は specialist コンポーネントの prompt body 内に出力スキーマキーワードが存在するかを検証しなければならない（SHALL）。

キーワードカテゴリ:
- `result_values`: PASS または FAIL のいずれか1つ以上
- `structure`: findings
- `severity`: severity
- `confidence`: confidence

全カテゴリのキーワードが body 内に出現すれば合格とする。

#### Scenario: 全キーワードが存在する specialist
- **WHEN** specialist の body に PASS, findings, severity, confidence が含まれる
- **THEN** deep-validate は WARNING を報告しない

#### Scenario: キーワードが不足している specialist
- **WHEN** specialist の body に findings が含まれるが severity が含まれない
- **THEN** deep-validate は `[specialist-output-schema]` WARNING を報告する

#### Scenario: PASS/FAIL のいずれか一方のみ存在
- **WHEN** specialist の body に FAIL は含まれるが PASS は含まれない
- **THEN** result_values カテゴリは合格とし WARNING を報告しない

### Requirement: output_schema custom によるスキップ

deps.yaml で `output_schema: custom` を持つ specialist は出力スキーマキーワード検証をスキップしなければならない（MUST）。

#### Scenario: output_schema が custom の specialist
- **WHEN** specialist の deps.yaml 定義に `output_schema: custom` が設定されている
- **THEN** deep-validate はその specialist の出力スキーマ検証をスキップする

#### Scenario: output_schema が不正値の specialist
- **WHEN** specialist の deps.yaml 定義に `output_schema: invalid` のように custom 以外の値が設定されている
- **THEN** deep-validate は `[specialist-output-schema]` WARNING を報告する

#### Scenario: output_schema フィールドが未設定の specialist
- **WHEN** specialist の deps.yaml 定義に `output_schema` フィールドがない
- **THEN** deep-validate は通常通りキーワード検証を実行する

## MODIFIED Requirements

### Requirement: audit Section 5 スキーマ準拠列の追加

audit Section 5 (Self-Contained) のテーブルに Schema 列を追加し、specialist の出力スキーマ準拠状況を表示しなければならない（SHALL）。

Schema 列の値:
- `Yes`: 全キーワードカテゴリが合格
- `No`: 不足キーワードあり
- `Skip`: output_schema: custom

#### Scenario: Schema 列が Yes の specialist
- **WHEN** specialist の body に全出力スキーマキーワードが含まれる
- **THEN** audit Section 5 の Schema 列に Yes と表示される

#### Scenario: Schema 列が Skip の specialist
- **WHEN** specialist の deps.yaml に output_schema: custom が設定されている
- **THEN** audit Section 5 の Schema 列に Skip と表示される

#### Scenario: Schema 不足が severity 判定に影響
- **WHEN** specialist の Purpose と Output は OK だが Schema が No
- **THEN** Section 5 の severity は WARNING となる
