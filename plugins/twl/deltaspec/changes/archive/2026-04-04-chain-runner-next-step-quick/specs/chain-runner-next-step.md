## ADDED Requirements

### Requirement: next-step コマンドの追加

`chain-runner.sh` は `next-step <issue_num> <current_step>` コマンドを提供しなければならない（SHALL）。このコマンドは `is_quick` と `current_step` を state から読み取り、次に実行すべきステップ名を stdout に返さなければならない（SHALL）。

#### Scenario: 通常 Issue の次ステップ返却

- **WHEN** `is_quick=false` の Issue で `current_step=init` の状態で `next-step` を呼ぶ
- **THEN** `worktree-create` を stdout に出力する

#### Scenario: quick Issue の QUICK_SKIP_STEPS 除外

- **WHEN** `is_quick=true` の Issue で `current_step=board-status-update` の状態で `next-step` を呼ぶ
- **THEN** crg-auto-build / arch-ref / opsx-propose / ac-extract をスキップし、`change-id-resolve` より後の非スキップステップ名を出力する（または ts-preflight）

#### Scenario: 全ステップ完了時

- **WHEN** `current_step` が CHAIN_STEPS の最終ステップ以降の場合
- **THEN** `done` を stdout に出力する

### Requirement: is_quick の state 永続化

`step_init` は quick ラベルの検出結果を `state-write.sh` 経由で issue-{N}.json に永続化しなければならない（SHALL）。永続化に失敗してもワークフロー全体を停止してはならない（MUST NOT）。

#### Scenario: quick ラベル付き Issue の永続化

- **WHEN** `step_init` が quick ラベルを検出した場合
- **THEN** `issue-{N}.json` に `is_quick=true` が書き込まれる

#### Scenario: quick ラベルなし Issue の永続化

- **WHEN** `step_init` が quick ラベルを検出しなかった場合
- **THEN** `issue-{N}.json` に `is_quick=false` が書き込まれる

### Requirement: QUICK_SKIP_STEPS 配列の追加

`chain-steps.sh` は `QUICK_SKIP_STEPS` 配列を定義しなければならない（SHALL）。この配列は quick Issue でスキップすべきステップ名を列挙する。

#### Scenario: QUICK_SKIP_STEPS のエクスポート

- **WHEN** `source scripts/chain-steps.sh` を実行する
- **THEN** `QUICK_SKIP_STEPS` 配列が利用可能になり、`crg-auto-build`, `arch-ref`, `opsx-propose`, `ac-extract`, `change-id-resolve`, `test-scaffold`, `check`, `opsx-apply` が含まれる

## MODIFIED Requirements

### Requirement: compaction-resume.sh の is_quick 対応

`compaction-resume.sh` は `is_quick` を state から取得し、quick スキップ対象ステップを除外しなければならない（SHALL）。

#### Scenario: quick Issue での QUICK_SKIP_STEPS スキップ

- **WHEN** `is_quick=true` の state で `compaction-resume.sh <N> opsx-propose` を呼ぶ
- **THEN** exit 1（スキップ）を返す

#### Scenario: 通常 Issue での QUICK_SKIP_STEPS 非スキップ

- **WHEN** `is_quick=false` の state で `compaction-resume.sh <N> opsx-propose` を呼ぶ
- **THEN** current_step との比較による通常のスキップ判定を行う

### Requirement: workflow-setup/SKILL.md の機械的 quick 分岐

`workflow-setup/SKILL.md` は quick 分岐の LLM 判断記述を除去し、`chain-runner.sh next-step` の出力に委譲する形式に書き換えなければならない（SHALL）。

#### Scenario: SKILL.md での next-step 利用

- **WHEN** setup chain の各ステップ完了後に next-step を呼ぶ
- **THEN** LLM は next-step の stdout 出力に従い次ステップを実行する（自然言語 quick 判定記述に依存しない）
