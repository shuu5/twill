## MODIFIED Requirements

### Requirement: pr-merge skip 分岐の削除

`autopilot-orchestrator.sh` の `inject_next_workflow()` は `pr-merge` または `/twl:workflow-pr-merge` を next_skill として検出した場合、inject をスキップせずに通常の allow-list バリデーション → input-waiting 検出 → `tmux send-keys` inject の経路を通らなければならない（SHALL）。

#### Scenario: warning-fix terminal で停止中の Worker に pr-merge を inject する

- **WHEN** Worker の `current_step=warning-fix` で chain が停止しており、`resolve_next_workflow.py` が `/twl:workflow-pr-merge` を返す
- **THEN** orchestrator は `/twl:workflow-pr-merge #${issue}` を `tmux send-keys` で inject し、trace log に `category=INJECT_SUCCESS skill=/twl:workflow-pr-merge` を記録しなければならない（SHALL）

#### Scenario: status=merge-ready 時は LAST_INJECTED_STEP による重複防止が機能する

- **WHEN** inject 成功後 `LAST_INJECTED_STEP[$entry]` が `warning-fix` に更新されており、次 poll で `current_step` が同じ値のまま
- **THEN** orchestrator は inject を再実行しない（SHALL）。`run_merge_gate` への流入のみが起こる

### Requirement: inject_next_workflow の連続 timeout 上限

`inject_next_workflow()` は pr-merge を next_skill として検出した際の inject timeout（input-waiting 未検出）が `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX`（デフォルト 5）回を超えた場合、`status=failed` + `failure.reason=inject_exhausted_pr_merge` を state に書き込み、`cleanup_worker` を呼び出して force-exit しなければならない（SHALL）。

#### Scenario: inject timeout が上限を超えた場合の force-exit

- **WHEN** `INJECT_TIMEOUT_COUNT[$entry]` が `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX` を超え、next_skill が pr-merge または /twl:workflow-pr-merge
- **THEN** orchestrator は `status=failed` と `failure.reason=inject_exhausted_pr_merge` を state ファイルに書き込み、`cleanup_worker` を呼び出さなければならない（SHALL）

#### Scenario: DEV_AUTOPILOT_INJECT_TIMEOUT_MAX 環境変数によるオーバーライド

- **WHEN** `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2` が設定されている
- **THEN** inject timeout が 3 回（2+1）到達した時点で force-exit が発動しなければならない（SHALL）

#### Scenario: inject 成功時にカウンタをリセットする

- **WHEN** pr-merge inject が成功（prompt_found=1）した
- **THEN** `INJECT_TIMEOUT_COUNT[$entry]` を 0 にリセットしなければならない（SHALL）

## ADDED Requirements

### Requirement: BATS テスト — pr-merge inject 経路の自動検証

新規ファイル `plugins/twl/tests/unit/inject-next-workflow/pr-merge-skip-guard.bats` は以下 3 ケースを検証しなければならない（SHALL）。

#### Scenario: (a) warning-fix 完了後に /twl:workflow-pr-merge が inject される

- **WHEN** Worker の `current_step=warning-fix`、`status=running`、resolve_next_workflow が `/twl:workflow-pr-merge` を返す状態で inject_next_workflow を呼び出す
- **THEN** `tmux send-keys` の引数に `/twl:workflow-pr-merge` が含まれ、trace log に `category=INJECT_SUCCESS skill=/twl:workflow-pr-merge` が記録されること

#### Scenario: (b) status=merge-ready かつ LAST_INJECTED_STEP 更新済みの場合は重複 inject されない

- **WHEN** `LAST_INJECTED_STEP[$entry]=warning-fix`、current_step が同値
- **THEN** inject_next_workflow が呼ばれず、`run_merge_gate` への流入のみが起こること

#### Scenario: (c) timeout 上限超過で status=failed と cleanup_worker が呼ばれる

- **WHEN** `DEV_AUTOPILOT_INJECT_TIMEOUT_MAX=2`、inject timeout を 3 回繰り返す
- **THEN** state に `status=failed` と `failure.reason=inject_exhausted_pr_merge` が書かれ、`cleanup_worker` が呼ばれること

### Requirement: アーキテクチャドキュメントへの再発防止メモ追記

`plugins/twl/architecture/domain/contexts/autopilot.md` には、pr-merge resolve 時の skip 判定が `status=merge-ready` 成立時のみ安全であること、および ADR-018 との相互参照を記載しなければならない（SHALL）。

#### Scenario: autopilot.md に状態遷移の注釈が含まれる

- **WHEN** `autopilot.md` の「状態遷移」セクション（L182 近辺）または「不変条件 M」セクション（L236 近辺）を参照する
- **THEN** 「pr-merge skip は status=merge-ready 成立時のみ安全（#744 修正済み）」と「merge-ready 書き込み責任者: Worker（chain-runner.sh `step_all_pass_check`）」の記述が含まれること（SHALL）
