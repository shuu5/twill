## ADDED Requirements

### Requirement: audit に Model Declaration セクションを追加

audit_report に Section 6: Model Declaration を追加しなければならない（SHALL）。全 specialist の model 宣言状況をテーブル形式で表示する。

#### Scenario: model 宣言済みの specialist
- **WHEN** specialist が `model: sonnet` を宣言している
- **THEN** テーブルに `| {name} | specialist | sonnet | OK |` を出力する

#### Scenario: model 未宣言の specialist
- **WHEN** specialist が model フィールドを持たない
- **THEN** テーブルに `| {name} | specialist | (none) | WARNING |` を出力し、warnings カウントを増やす

#### Scenario: 未知の model 値の specialist
- **WHEN** specialist が ALLOWED_MODELS にない model 値を宣言している
- **THEN** テーブルに `| {name} | specialist | {value} | INFO |` を出力する

#### Scenario: opus を宣言した specialist
- **WHEN** specialist が `model: opus` を宣言している
- **THEN** テーブルに `| {name} | specialist | opus | WARNING |` を出力し、warnings カウントを増やす

### Requirement: audit Model Declaration テーブルフォーマット

Section 6 のテーブルは以下のヘッダーを持たなければならない（MUST）: `| Name | Type | Model | Severity |`

#### Scenario: テーブルヘッダー
- **WHEN** audit を実行する
- **THEN** Section 6 が `## 6. Model Declaration` で始まり、`| Name | Type | Model | Severity |` ヘッダーを持つ
