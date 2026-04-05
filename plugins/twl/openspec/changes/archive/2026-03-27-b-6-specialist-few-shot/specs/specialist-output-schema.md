## ADDED Requirements

### Requirement: ref-specialist-output-schema reference コンポーネント

`refs/ref-specialist-output-schema.md` を作成し、全 specialist の出力形式を定義しなければならない（MUST）。

スキーマは以下の必須フィールドを含まなければならない（SHALL）:
- `status`: PASS / WARN / FAIL の 3 値（findings の severity から自動導出）
- `findings`: 配列。各要素に severity, confidence, file, line, message, category を持つ
- `severity`: CRITICAL / WARNING / INFO の 3 段階
- `confidence`: 0-100 の整数。merge-gate フィルタ閾値は `>= 80`
- `category`: vulnerability / bug / coding-convention / structure / principles の 5 種

#### Scenario: スキーマ必須フィールドの定義
- **WHEN** ref-specialist-output-schema.md を検査する
- **THEN** status, findings, severity, confidence, file, line, message, category の全フィールドが定義されている

#### Scenario: severity 3 段階の定義
- **WHEN** severity の定義を確認する
- **THEN** CRITICAL, WARNING, INFO の 3 値のみが許可されている
- **AND** 旧表記（Critical, High, Medium, Suggestion, Info）からの変換マッピングが記載されている

### Requirement: status 自動導出ルール

status は findings 配列の severity から機械的に導出しなければならない（MUST）。AI の裁量で status を決定してはならない（SHALL）。

導出ルール:
1. findings に `severity == "CRITICAL"` が 1 件以上 → `FAIL`
2. findings に `severity == "WARNING"` が 1 件以上 → `WARN`
3. それ以外 → `PASS`

#### Scenario: FAIL 判定
- **WHEN** findings に severity=CRITICAL のエントリが 1 件以上存在する
- **THEN** status は FAIL である

#### Scenario: WARN 判定
- **WHEN** findings に severity=CRITICAL がなく severity=WARNING が 1 件以上存在する
- **THEN** status は WARN である

#### Scenario: PASS 判定
- **WHEN** findings が空、または全て severity=INFO である
- **THEN** status は PASS である

### Requirement: 消費側パースルール

merge-gate / phase-review が specialist 出力を消費するためのパースルールを定義しなければならない（MUST）。

パースルールは以下を含まなければならない（SHALL）:
- サマリー行パース: 正規表現 `status: (PASS|WARN|FAIL)` で status を取得
- ブロック判定: `severity == CRITICAL && confidence >= 80` で REJECT
- パース失敗時フォールバック: 出力全文を WARNING (confidence=50) として扱い手動レビュー要求

#### Scenario: サマリー行パースの成功
- **WHEN** specialist 出力に `status: FAIL` が含まれる
- **THEN** 消費側は status=FAIL を取得する

#### Scenario: ブロック判定（REJECT）
- **WHEN** findings に severity=CRITICAL かつ confidence=95 のエントリがある
- **THEN** merge-gate は REJECT を返す

#### Scenario: ブロック判定（PASS — confidence 不足）
- **WHEN** findings に severity=CRITICAL かつ confidence=60 のエントリがある
- **THEN** merge-gate は PASS を返す（confidence < 80 のため）

#### Scenario: パース失敗時のフォールバック
- **WHEN** specialist 出力が共通スキーマに準拠しない
- **THEN** 出力全文が 1 つの WARNING finding (confidence=50) として扱われる
- **AND** 手動レビューが要求される

### Requirement: output_schema: custom 除外条件

特定の specialist が独自出力形式を使用する場合の除外ルールを定義しなければならない（MUST）。

deps.yaml の specialist/agent エントリに `output_schema: custom` を指定した場合、共通スキーマの適用を免除しなければならない（SHALL）。ただし、消費側（merge-gate）でのパース失敗フォールバックは適用される。

#### Scenario: output_schema: custom の除外
- **WHEN** specialist の deps.yaml エントリに `output_schema: custom` が指定されている
- **THEN** 共通出力スキーマの few-shot テンプレートは注入されない

#### Scenario: custom specialist のフォールバック処理
- **WHEN** output_schema: custom の specialist が自由形式で出力する
- **THEN** merge-gate はパース失敗フォールバック（WARNING, confidence=50）を適用する
