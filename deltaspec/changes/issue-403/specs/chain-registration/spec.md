## ADDED Requirements

### Requirement: chain-steps.sh への phase-review/scope-judge 登録

chain-steps.sh の CHAIN_STEPS 配列（pr-verify セクション）に `phase-review` と `scope-judge` が登録されなければならない（SHALL）。登録順序は `ts-preflight` の直後、`pr-test` の前でなければならない（SHALL）。

#### Scenario: pr-verify chain のステップ順序確認
- **WHEN** chain-steps.sh の CHAIN_STEPS 配列（pr-verify セクション）を参照する
- **THEN** `ts-preflight`, `phase-review`, `scope-judge`, `pr-test` の順で定義されている

#### Scenario: STEP_DISPATCH_MODE マップへの登録
- **WHEN** chain-steps.sh の STEP_DISPATCH_MODE マップを参照する
- **THEN** `phase-review` が `llm`、`scope-judge` が `llm` として登録されている

#### Scenario: STEP_CMD マップへの登録
- **WHEN** chain-steps.sh の STEP_CMD マップを参照する
- **THEN** `phase-review` が `commands/phase-review.md`、`scope-judge` が `commands/scope-judge.md` として登録されている

### Requirement: CHAIN_STEP_TO_WORKFLOW への phase-review/scope-judge 登録

chain-steps.sh の CHAIN_STEP_TO_WORKFLOW マップに `phase-review` → `pr-verify`、`scope-judge` → `pr-verify` が登録されなければならない（SHALL）。

#### Scenario: CHAIN_STEP_TO_WORKFLOW マップ確認
- **WHEN** chain-steps.sh の CHAIN_STEP_TO_WORKFLOW マップを参照する
- **THEN** `phase-review` と `scope-judge` がともに `pr-verify` にマッピングされている

### Requirement: chain.py STEP_TO_WORKFLOW への登録

chain.py の STEP_TO_WORKFLOW 辞書に `phase-review` → `"pr-verify"`、`scope-judge` → `"pr-verify"` が登録されなければならない（SHALL）。

#### Scenario: chain.py の STEP_TO_WORKFLOW 確認
- **WHEN** cli/twl/src/twl/autopilot/chain.py の STEP_TO_WORKFLOW を参照する
- **THEN** `"phase-review"` と `"scope-judge"` がともに `"pr-verify"` にマッピングされている

### Requirement: chain-runner.sh への phase-review/scope-judge ハンドラ追加

chain-runner.sh の `case "$step"` ブロックに `phase-review` と `scope-judge` のハンドラが追加されなければならない（SHALL）。ハンドラは既存の llm dispatch パターン（`record_current_step` + `ok` メッセージ）に準拠しなければならない（MUST）。

#### Scenario: phase-review ハンドラの実行
- **WHEN** `chain-runner.sh phase-review` を実行する
- **THEN** "ERROR: 未知のステップ" を出力せずに正常終了する
- **THEN** `.autopilot/issues/issue-N.json` の `current_step` が `phase-review` に更新される

#### Scenario: scope-judge ハンドラの実行
- **WHEN** `chain-runner.sh scope-judge` を実行する
- **THEN** "ERROR: 未知のステップ" を出力せずに正常終了する
- **THEN** `.autopilot/issues/issue-N.json` の `current_step` が `scope-judge` に更新される

## ADDED Requirements

### Requirement: chain trace への phase-review イベント記録（自動テスト）

autopilot 実行時の chain trace JSONL に phase-review の start/end イベントが記録されなければならない（SHALL）。この動作を確認する自動テストが存在しなければならない（MUST）。

#### Scenario: chain trace への phase-review 記録
- **WHEN** pr-verify chain が実行される
- **THEN** `.autopilot/trace/` の JSONL に `phase-review` の `start` イベントが記録される
- **THEN** `.autopilot/trace/` の JSONL に `phase-review` の `end` イベントが記録される

#### Scenario: 自動テストによる検証
- **WHEN** `pytest cli/twl/tests/` を実行する
- **THEN** phase-review と scope-judge が pr-verify chain の正しい順序位置に登録されていることを検証するテストが PASS する
