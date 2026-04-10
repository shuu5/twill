## MODIFIED Requirements

### Requirement: chain-steps.sh の post-change-apply dispatch_mode を runner に統一する

`chain-steps.sh` の `CHAIN_STEP_DISPATCH` 配列で `post-change-apply` のエントリが `runner` に設定されなければならない（SHALL）。

#### Scenario: twl check が Critical エラーなしで通過する
- **WHEN** `twl check` を実行する
- **THEN** `post-change-apply: dispatch_mode mismatch` の Critical エラーが報告されない

#### Scenario: chain-runner.sh の llm-delegate で警告が出ない
- **WHEN** `chain-runner.sh llm-delegate post-change-apply` を呼び出す
- **THEN** dispatch_mode が `llm` でないことへの WARN が出ない（そもそも llm-delegate を呼ぶべきでないことが明確になる）

### Requirement: chain-runner.sh の post-change-apply コメントを実態に合わせる

`chain-runner.sh` の `post-change-apply` ケースのコメントが実際の動作を正確に記述しなければならない（MUST）。

#### Scenario: コメントが runner パターンを正確に表現する
- **WHEN** `chain-runner.sh` の `post-change-apply` ケースを参照する
- **THEN** "LLM スキル実行" ではなく "runner ステップ記録" であることが明確に読み取れる
