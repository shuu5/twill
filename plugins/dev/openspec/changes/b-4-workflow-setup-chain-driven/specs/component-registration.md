## ADDED Requirements

### Requirement: 新規 atomic コンポーネント登録

setup chain に参加するコンポーネントのうち、deps.yaml に未登録のものを commands セクションに atomic 型として登録しなければならない（SHALL）。各エントリに path, description, spawnable_by, can_spawn, chain, step_in を設定する（MUST）。

#### Scenario: 全 chain 参加コンポーネントが登録済み
- **WHEN** deps.yaml の commands セクションを確認する
- **THEN** init, worktree-create, worktree-delete, worktree-list, project-board-status-update, crg-auto-build, opsx-propose, opsx-apply, opsx-archive, ac-extract が atomic として登録されている

#### Scenario: spawnable_by が正しい
- **WHEN** chain 参加コンポーネントの spawnable_by を確認する
- **THEN** 全コンポーネントが `[controller, workflow]` を含む

### Requirement: workflow-setup の workflow 型登録

workflow-setup を deps.yaml の skills セクションに workflow 型として登録しなければならない（SHALL）。calls フィールドで chain 内の全ステップを step 番号付きで参照する（MUST）。

#### Scenario: workflow 型として登録
- **WHEN** deps.yaml の skills セクションを確認する
- **THEN** workflow-setup が `type: workflow` で登録され、`chain: "setup"` が設定されている

#### Scenario: calls が全ステップを網羅
- **WHEN** workflow-setup の calls を確認する
- **THEN** step "1"（init）から step "4"（workflow-test-ready）まで全 chain 参加コンポーネントが calls に含まれる

### Requirement: workflow-test-ready の workflow 型登録

workflow-test-ready を deps.yaml の skills セクションに workflow 型として登録しなければならない（SHALL）。setup chain の最終ステップとして step_in を設定する（MUST）。

#### Scenario: workflow 型として登録
- **WHEN** deps.yaml の skills セクションを確認する
- **THEN** workflow-test-ready が `type: workflow` で登録され、`chain: "setup"` と `step_in` が設定されている
