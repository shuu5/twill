## ADDED Requirements

### Requirement: ref-specialist-few-shot reference コンポーネント

`refs/ref-specialist-few-shot.md` を作成し、specialist プロンプト用の few-shot テンプレート（1 例）を定義しなければならない（MUST）。

テンプレートは以下を含まなければならない（SHALL）:
- FAIL ケースの完全な出力例（status, findings 配列）
- findings に CRITICAL, WARNING, INFO の 3 severity レベルを含む例
- 各 finding に file, line, confidence, message, category の全フィールドを含む例
- specialist 名のプレースホルダー `{specialist-name}`

#### Scenario: few-shot テンプレートの構造
- **WHEN** ref-specialist-few-shot.md を検査する
- **THEN** FAIL ケースの出力例が 1 つ存在する
- **AND** findings に CRITICAL, WARNING, INFO の 3 レベルが全て含まれている

#### Scenario: findings 必須フィールドの網羅
- **WHEN** few-shot テンプレートの各 finding を検査する
- **THEN** severity, confidence, file, line, message, category の全フィールドが存在する

### Requirement: コンテキスト消費の最小化

few-shot テンプレートは 1 例のみとしなければならない（MUST）。複数例を含めてはならない（SHALL）。

ADR-004 の判断に基づき、コンテキスト消費（約 150 tokens/例）と準拠率（72-90%）のトレードオフから 1 例を選択する。

#### Scenario: テンプレート例数の制限
- **WHEN** ref-specialist-few-shot.md の出力例の数を数える
- **THEN** 1 例のみである

### Requirement: specialist プロンプトへの注入形式

few-shot テンプレートは specialist プロンプトの末尾に `## 出力形式（MUST）` セクションとして注入する形式を定義しなければならない（MUST）。

注入セクションは以下を含まなければならない（SHALL）:
- セクションヘッダー: `## 出力形式（MUST）`
- 形式説明: 「以下の形式で出力すること」
- コードブロック内の完全な出力例

#### Scenario: 注入セクションの形式
- **WHEN** few-shot テンプレートの注入セクションを検査する
- **THEN** `## 出力形式（MUST）` ヘッダーが存在する
- **AND** コードブロック内に完全な出力例が含まれている

### Requirement: Model 割り当て表の包含

ref-specialist-output-schema に specialist ごとの model 割り当て（haiku/sonnet）を記載しなければならない（MUST）。

割り当て基準は以下に従わなければならない（SHALL）:
- haiku: 構造チェック・パターンマッチ（LLM 判断最小限）
- sonnet: コードレビュー・品質判断・コード生成（LLM 判断力必要）
- opus: specialist には使用しない（Controller/Workflow のみ）

#### Scenario: model 割り当て表の存在
- **WHEN** ref-specialist-output-schema.md の model 割り当てセクションを検査する
- **THEN** haiku と sonnet の specialist 一覧が記載されている

#### Scenario: opus が specialist に割り当てられていない
- **WHEN** model 割り当て表を検査する
- **THEN** opus に割り当てられた specialist は 0 件である
