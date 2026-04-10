## MODIFIED Requirements

### Requirement: step_next_step が DIRECT_SKIP_STEPS を参照する

`chain-runner.sh` の `step_next_step()` は `mode=direct` 時に `DIRECT_SKIP_STEPS` に含まれるステップをスキップしなければならない（SHALL）。

#### Scenario: mode=direct 時に change-propose がスキップされる
- **WHEN** state の `mode` フィールドが `"direct"` であり、`step_next_step` が `change-propose` の前のステップを `current_step` として呼ばれる
- **THEN** `change-propose` を返さず、`DIRECT_SKIP_STEPS` に含まれない次のステップを返す

#### Scenario: mode=direct 時に change-id-resolve がスキップされる
- **WHEN** state の `mode` フィールドが `"direct"` であり、`step_next_step` が `change-id-resolve` の前のステップを `current_step` として呼ばれる
- **THEN** `change-id-resolve` を返さず、`DIRECT_SKIP_STEPS` に含まれない次のステップを返す

#### Scenario: mode=direct 時に change-apply がスキップされる
- **WHEN** state の `mode` フィールドが `"direct"` であり、`step_next_step` が `change-apply` の前のステップを `current_step` として呼ばれる
- **THEN** `change-apply` を返さず、`DIRECT_SKIP_STEPS` に含まれない次のステップを返す

#### Scenario: mode が direct 以外の場合は DIRECT_SKIP_STEPS をスキップしない
- **WHEN** state の `mode` フィールドが `"propose"` または `"apply"` であり、`step_next_step` が呼ばれる
- **THEN** `DIRECT_SKIP_STEPS` に含まれるステップも通常通り返す

### Requirement: step_chain_status が DIRECT_SKIP_STEPS を正しく表示する

`chain-runner.sh` の `step_chain_status()` は `mode=direct` 時に `DIRECT_SKIP_STEPS` に含まれるステップを `⊘ ... (skipped/direct)` として表示しなければならない（SHALL）。

#### Scenario: mode=direct 時に skipped/direct ラベルが表示される
- **WHEN** state の `mode` フィールドが `"direct"` であり、`chain-status` コマンドが実行される
- **THEN** `change-propose`・`change-id-resolve`・`change-apply` のステップに `⊘ <step> [<dispatch>] (skipped/direct)` が表示される

#### Scenario: mode が direct 以外の場合は通常表示される
- **WHEN** state の `mode` フィールドが `"direct"` でない場合に `chain-status` コマンドが実行される
- **THEN** `DIRECT_SKIP_STEPS` に含まれるステップが `(skipped/direct)` として表示されない
