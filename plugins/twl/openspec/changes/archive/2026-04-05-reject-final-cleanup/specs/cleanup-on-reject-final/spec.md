## MODIFIED Requirements

### Requirement: reject-final確定失敗後のworktreeとリモートブランチのクリーンアップ

orchestratorのmerge-gateループにおいて、`--reject-final`（確定失敗）の結果として`status=failed`かつ`failure.reason=merge_gate_rejected_final`となった場合、top-level `retry_count`の値に関わらず`cleanup_worker`を呼ばなければならない（SHALL）。

#### Scenario: 初回実行でreject-final（retry_count=0）

- **WHEN** Issueが`merge-ready`状態で、merge-gateが`--reject-final`を呼び、`status=failed`・`failure.reason=merge_gate_rejected_final`・top-level `retry_count=0`の状態になった後、orchestratorのmerge-gateループが結果を評価するとき
- **THEN** `cleanup_worker`が呼ばれ、worktreeとリモートブランチが削除されなければならない（SHALL）

#### Scenario: リトライ後のreject-final（retry_count>=1）

- **WHEN** Issueが一度リトライされた後（`retry_count=1`）、merge-gateが`--reject-final`を呼んだとき
- **THEN** 既存の`retry_count >= 1`条件が真となり、`cleanup_worker`が呼ばれる（既存動作の維持）

#### Scenario: 通常reject（retry_count=0、リトライ可）

- **WHEN** Issueが`merge-ready`状態で、merge-gateが`--reject`（リトライ可）を呼び、`status=failed`・`failure.reason=merge_gate_rejected`・top-level `retry_count=0`になったとき
- **THEN** `cleanup_worker`が呼ばれず、Issueはリトライ対象として残らなければならない（SHALL NOT cleanup）

### Requirement: failure.reasonによるreject-final識別

orchestratorはstateファイルの`failure.reason`フィールドを読み取り、`"merge_gate_rejected_final"`と一致する場合にのみreject-final確定失敗と識別しなければならない（SHALL）。

#### Scenario: failure.reasonが存在しない古いstateファイル

- **WHEN** stateファイルに`failure`オブジェクトがない（または`failure.reason`がnull）とき
- **THEN** `_failure_reason`は空文字列となり、既存の`retry_count >= 1`判定のみが適用されなければならない（SHALL）。動作は修正前と同一であること
