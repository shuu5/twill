## ADDED Requirements

### Requirement: 調査バジェット共通 ref の作成

`refs/ref-investigation-budget.md` を新規作成し、調査バジェット制御ルールを一元管理しなければならない（SHALL）。本文は `issue-critic.md` の現行セクション（L62-69）と行単位一致で同一でなければならない（SHALL）。

#### Scenario: ref ファイル作成
- **WHEN** `refs/ref-investigation-budget.md` が作成される
- **THEN** ファイルが存在し、`issue-critic.md` の調査バジェット制御セクションと行単位一致である

## MODIFIED Requirements

### Requirement: issue-critic.md の ref 参照化

`agents/issue-critic.md` は重複する調査バジェット制御セクションを削除し、ref 参照指示に置換しなければならない（MUST）。frontmatter の `skills:` フィールドに `ref-investigation-budget` を追加しなければならない（MUST）。

#### Scenario: issue-critic が ref を参照する
- **WHEN** `agents/issue-critic.md` を Read する
- **THEN** frontmatter の `skills:` に `ref-investigation-budget` が含まれ、本文に「`**/refs/ref-investigation-budget.md` を Glob/Read して調査バジェットを確認すること」という指示が含まれる

#### Scenario: issue-critic に重複セクションが存在しない
- **WHEN** `agents/issue-critic.md` を Read する
- **THEN** 「調査バジェット制御（MUST）」セクションが本文に直接存在しない

### Requirement: issue-feasibility.md の ref 参照化

`agents/issue-feasibility.md` は `issue-critic.md` と同様の変更を適用しなければならない（MUST）。

#### Scenario: issue-feasibility が ref を参照する
- **WHEN** `agents/issue-feasibility.md` を Read する
- **THEN** frontmatter の `skills:` に `ref-investigation-budget` が含まれ、ref 参照指示が含まれる

#### Scenario: issue-feasibility に重複セクションが存在しない
- **WHEN** `agents/issue-feasibility.md` を Read する
- **THEN** 「調査バジェット制御（MUST）」セクションが本文に直接存在しない

### Requirement: deps.yaml の更新

`deps.yaml` の refs セクションに `ref-investigation-budget` を追加し、`issue-critic` と `issue-feasibility` の `skills:` フィールドに追加しなければならない（MUST）。

#### Scenario: deps.yaml 整合性
- **WHEN** `loom check` を実行する
- **THEN** エラーなく完了する

### Requirement: テストの更新

`tests/scenarios/co-issue-specialist-maxturns-fix.test.sh` の assert を更新し、agent 本文の「調査バジェット制御」文言チェックを、ref ファイルまたは frontmatter の skills 参照チェックに変更しなければならない（MUST）。

#### Scenario: テスト PASS
- **WHEN** `tests/scenarios/co-issue-specialist-maxturns-fix.test.sh` を実行する
- **THEN** 全 assert が PASS する
