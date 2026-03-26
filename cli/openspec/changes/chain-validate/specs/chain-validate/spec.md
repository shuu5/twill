## ADDED Requirements

### Requirement: chain 双方向整合性検証
`chains.steps` に登録された各コンポーネントが対応する `chain` フィールドを持ち、逆方向（`chain` フィールドを持つコンポーネントが `chains.steps` に含まれること）も成立することを検証しなければならない（SHALL）。

#### Scenario: chains.steps にあるが component.chain がない
- **WHEN** `chains.workflow-setup.steps` に `ac-extract` が含まれるが、`ac-extract` の `chain` フィールドが未設定
- **THEN** CRITICAL エラー `[chain-bidir] ac-extract: listed in chains/workflow-setup/steps but has no chain field` を出力する

#### Scenario: component.chain があるが chains.steps にない
- **WHEN** コンポーネント `ac-verify` が `chain: workflow-setup` を持つが、`chains.workflow-setup.steps` に `ac-verify` が含まれない
- **THEN** CRITICAL エラー `[chain-bidir] ac-verify: chain='workflow-setup' but not listed in chains/workflow-setup/steps` を出力する

#### Scenario: 双方向が一致している
- **WHEN** `chains.pr-cycle.steps` に `test-phase` が含まれ、`test-phase` の `chain` が `pr-cycle`
- **THEN** エラーを出力せず ok_count を加算する

### Requirement: step 双方向整合性検証
`parent.calls[].step` で指定された子コンポーネントが `step_in: {parent: parent_name}` で逆参照し、逆方向も成立することを検証しなければならない（SHALL）。

#### Scenario: calls に step があるが child に step_in がない
- **WHEN** `workflow-setup` の calls に `{atomic: ac-extract, step: "1.5"}` があるが、`ac-extract` の `step_in` が未設定
- **THEN** CRITICAL エラー `[step-bidir] ac-extract: called with step='1.5' from workflow-setup but has no step_in` を出力する

#### Scenario: child に step_in があるが parent の calls に step がない
- **WHEN** `ac-verify` が `step_in: {parent: workflow-setup}` を持つが、`workflow-setup` の calls に `ac-verify` への step 指定がない
- **THEN** CRITICAL エラー `[step-bidir] ac-verify: step_in.parent='workflow-setup' but workflow-setup has no step call to ac-verify` を出力する

#### Scenario: step 双方向が一致している
- **WHEN** `workflow-setup` の calls に `{atomic: ac-extract, step: "1.5"}` があり、`ac-extract` が `step_in: {parent: workflow-setup}` を持つ
- **THEN** エラーを出力せず ok_count を加算する

### Requirement: Chain 参加者型制約検証
Chain の `type` フィールドに基づき、参加者の型が許可範囲内であることを検証しなければならない（MUST）。Chain A は `workflow|atomic` のみ、Chain B は `atomic|composite` のみを許可する。

#### Scenario: Chain A に specialist が参加
- **WHEN** `chains.setup-flow` の `type` が `A` で、steps に型 `specialist` のコンポーネントが含まれる
- **THEN** WARNING `[chain-type] chains/setup-flow: specialist 'worker-xxx' not allowed in Chain A (allowed: workflow, atomic)` を出力する

#### Scenario: Chain B に workflow が参加
- **WHEN** `chains.review-flow` の `type` が `B` で、steps に型 `workflow` のコンポーネントが含まれる
- **THEN** WARNING `[chain-type] chains/review-flow: workflow 'workflow-xxx' not allowed in Chain B (allowed: atomic, composite)` を出力する

#### Scenario: Chain に type フィールドがない場合
- **WHEN** chain 定義に `type` フィールドが存在しない
- **THEN** 型制約チェックをスキップし、エラーも警告も出力しない

### Requirement: step 番号昇順検証
1つのコンポーネントの `calls` 配列内で、`step` フィールドを持つエントリの step 値が昇順であることを検証しなければならない（SHALL）。

#### Scenario: step 番号が降順
- **WHEN** `workflow-pr-cycle` の calls が `[{step: "3"}, {step: "1.5"}, {step: "5"}]` の順で並んでいる
- **THEN** WARNING `[step-order] workflow-pr-cycle: step '1.5' appears after '3' (not ascending)` を出力する

#### Scenario: step 番号が昇順
- **WHEN** calls が `[{step: "1"}, {step: "1.5"}, {step: "3"}]` の順で並んでいる
- **THEN** エラーを出力せず ok_count を加算する

### Requirement: プロンプト body 整合性検証
プロンプト body 内の chain/step 関連参照（`/{plugin}:{name}` パターンと `Step {N} から呼び出される` パターン）が deps.yaml の chains/step 情報と整合することを検証しなければならない（SHALL）。

#### Scenario: body に「Step N から呼び出される」と記載があるが step_in がない
- **WHEN** コンポーネントの body に `workflow-pr-cycle Step 3.5 から呼び出される` と記載があるが、deps.yaml に対応する `step_in` がない
- **THEN** WARNING `[prompt-chain] xxx: body mentions 'workflow-pr-cycle Step 3.5' but no matching step_in in deps.yaml` を出力する

#### Scenario: body の参照と deps.yaml が一致
- **WHEN** body に `workflow-pr-cycle Step 3.5 から呼び出される` と記載があり、deps.yaml に `step_in: {parent: workflow-pr-cycle}` が存在する
- **THEN** エラーを出力せず ok_count を加算する

## MODIFIED Requirements

### Requirement: loom check への chain 検証統合
`loom check` 実行時に deps.yaml が v3.0 であることを検出した場合、`chain_validate` を自動的に呼び出さなければならない（MUST）。

#### Scenario: v3.0 deps.yaml で loom check 実行
- **WHEN** `loom check` が v3.0 の deps.yaml を持つプラグインで実行される
- **THEN** ファイル存在チェックに加えて chain 検証結果も表示され、CRITICAL があれば非ゼロ終了する

#### Scenario: v2.0 deps.yaml で loom check 実行
- **WHEN** `loom check` が v2.0 の deps.yaml を持つプラグインで実行される
- **THEN** chain 検証は実行されず、従来のファイル存在チェックのみが行われる
