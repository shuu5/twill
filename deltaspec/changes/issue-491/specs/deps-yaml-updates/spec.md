## MODIFIED Requirements

### Requirement: deps.yaml spawnable_by 拡張

以下の 5 コンポーネントの `spawnable_by` が `[controller]` から `[controller, workflow]` に拡張されなければならない（SHALL）:
- `issue-structure`
- `issue-spec-review` (composite)
- `issue-review-aggregate`
- `issue-arch-drift`
- `issue-create`

#### Scenario: issue-structure spawnable_by
- **WHEN** deps.yaml の issue-structure エントリを確認する
- **THEN** `spawnable_by` に `workflow` が含まれる

#### Scenario: twl check PASS
- **WHEN** spawnable_by 拡張後に `twl check` を実行する
- **THEN** 型制約違反なしで PASS する

## ADDED Requirements

### Requirement: deps.yaml 新エントリ追加

`workflow-issue-lifecycle` (type: workflow) と `issue-lifecycle-orchestrator` (type: script) の 2 件が deps.yaml に追加されなければならない（SHALL）。

#### Scenario: workflow-issue-lifecycle エントリ
- **WHEN** deps.yaml を確認する
- **THEN** `workflow-issue-lifecycle` エントリが `type: workflow`, `spawnable_by: [controller, user]`, `can_spawn: [composite, atomic, specialist]` を含む

#### Scenario: issue-lifecycle-orchestrator エントリ
- **WHEN** deps.yaml を確認する
- **THEN** `issue-lifecycle-orchestrator` エントリが scripts セクションに存在する
