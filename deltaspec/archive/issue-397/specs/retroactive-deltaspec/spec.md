## ADDED Requirements

### Requirement: Retroactive DeltaSpec モード検出

workflow-setup の init ステップは、ブランチの diff が DeltaSpec ドキュメントのみを含み実装コード（*.py, *.sh, *.ts 等）を含まない場合、`deltaspec_mode: retroactive` を自動設定しなければならない（SHALL）。

#### Scenario: 実装コードなし・ドキュメントのみの差分
- **WHEN** `git diff origin/main...HEAD` が DeltaSpec ファイルのみを含む
- **THEN** `issue-<N>.json` の `deltaspec_mode` が `retroactive` に設定される

#### Scenario: 実装コードが含まれる通常ケース
- **WHEN** `git diff origin/main...HEAD` に *.py / *.sh / *.ts 等が含まれる
- **THEN** `deltaspec_mode` は設定されない（通常モード）

---

### Requirement: Implementation PR の追跡

autopilot state（`issue-<N>.json`）は `implementation_pr` フィールドをサポートしなければならない（SHALL）。このフィールドは、当該 Issue の実装が行われた外部 PR の番号を保持する。

#### Scenario: Issue body からの自動検出
- **WHEN** Issue body に `Implemented-in: #<N>` タグが存在する
- **THEN** `implementation_pr` が自動的に `<N>` に設定される

#### Scenario: 自動検出できない場合の手動入力
- **WHEN** Issue body に `Implemented-in` タグが存在しない
- **THEN** ユーザーに `implementation_pr` の入力を求めるプロンプトが表示される

---

### Requirement: Cross-PR AC 検証

merge-gate は `implementation_pr` が設定されている場合、AC 検証を本 PR の diff ではなく参照 PR のマージコミットに対して実行しなければならない（MUST）。

#### Scenario: implementation_pr が設定されている場合の AC 検証
- **WHEN** `issue-<N>.json` に `implementation_pr: 392` が設定されている
- **THEN** `gh pr view 392 --json mergeCommit` でコミット SHA を取得し、そのコミットに対して AC チェックを実行する

#### Scenario: implementation_pr が未設定の場合（通常モード）
- **WHEN** `issue-<N>.json` に `implementation_pr` が存在しない
- **THEN** 通常通り本 PR の diff に対して AC チェックを実行する

## MODIFIED Requirements

### Requirement: workflow-setup init の retroactive 対応

workflow-setup の init ステップは、retroactive モードを検出した場合に `recommended_action` を通常の `propose` / `apply` ではなく `retroactive_propose` として返さなければならない（SHALL）。

#### Scenario: retroactive モードでの init 結果
- **WHEN** init が retroactive モードを検出する
- **THEN** `recommended_action: retroactive_propose` が返され、`implementation_pr` の確認ステップが挿入される
