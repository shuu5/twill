## MODIFIED Requirements

### Requirement: Script calls 宣言

コマンドが実行するスクリプトは、そのコマンドの `calls` に `- script: <name>` として宣言しなければならない（SHALL）。
スクリプト実行パターン（`$SCRIPT_DIR/xxx.sh`、`bash "$SCRIPT_DIR/xxx.sh"`、`scripts/xxx.sh`）を含むコマンドは全て対象とする（MUST）。

#### Scenario: コマンドがスクリプトを実行する場合
- **WHEN** command:worktree-create が scripts/worktree-create.sh を実行する
- **THEN** deps.yaml の worktree-create コマンドエントリに `calls: [- script: worktree-create]` が存在する

#### Scenario: 複数スクリプトを実行するコマンド
- **WHEN** command:autopilot-init が scripts/autopilot-init.sh と scripts/session-create.sh を実行する
- **THEN** deps.yaml の autopilot-init コマンドエントリの calls に両方の script エントリが存在する

### Requirement: Agent calls 宣言

composite コマンドが動的に spawn する specialist agent は、その composite の `calls` に `- agent: <name>` として宣言しなければならない（SHALL）。
`can_spawn: [specialist]` を持つ composite は、spawn 候補の全 agent を列挙すること（MUST）。

#### Scenario: composite が specialist を spawn する場合
- **WHEN** command:phase-review が tech-stack-detect 結果に基づき specialist を動的選択する
- **THEN** deps.yaml の phase-review エントリの calls に全候補 agent が `- agent:` 形式で列挙されている

#### Scenario: 固定 specialist を spawn する composite
- **WHEN** command:issue-assess が template-validator と context-checker を spawn する
- **THEN** deps.yaml の issue-assess エントリの calls に `- agent: template-validator` と `- agent: context-checker` が存在する

### Requirement: Reference calls 宣言

コンポーネントが参照する reference は、そのコンポーネントの `calls` に `- reference: <name>` として宣言しなければならない（SHALL）。
ただし agent 型（type: specialist）は `calls` フィールドを持てないため、agent を spawn する composite 側に reference calls を追加すること（MUST）。

#### Scenario: コマンドが reference を直接参照する場合
- **WHEN** command:issue-structure が refs/ref-issue-template-bug.md を参照する
- **THEN** co-issue controller（issue-structure を calls する側）の calls に `- reference: ref-issue-template-bug` が存在する

#### Scenario: agent が reference を参照する場合
- **WHEN** agent:worker-code-reviewer が refs/baseline-coding-style.md を参照する
- **THEN** worker-code-reviewer を spawn する composite（phase-review, merge-gate 等）の calls に `- reference: baseline-coding-style` が存在する

### Requirement: Workflow calls 宣言

controller が Skill tool で起動する workflow は、その controller の `calls` に `- workflow: <name>` として宣言しなければならない（SHALL）。

#### Scenario: controller が workflow を起動する場合
- **WHEN** co-autopilot が `/twl:workflow-setup` を Skill tool で起動する
- **THEN** deps.yaml の co-autopilot エントリの calls に `- workflow: workflow-setup` が存在する

#### Scenario: 全 workflow が参照される
- **WHEN** `loom orphans` を実行する
- **THEN** 5 件の workflow（workflow-setup, workflow-test-ready, workflow-pr-cycle, workflow-dead-cleanup, workflow-tech-debt-triage）が Unused セクションに表示されない

### Requirement: Sub-command calls 宣言

親コマンドがチェックポイントや明示的呼び出しで起動する sub-command は、親の `calls` に宣言しなければならない（SHALL）。
コマンド .md 末尾の「チェックポイント（MUST）」セクションで参照されるコマンドは全て対象とする（MUST）。

#### Scenario: チェックポイントでの sub-command 呼び出し
- **WHEN** command:worktree-create の末尾に「`/twl:project-board-status-update` を Skill tool で自動実行」と記載されている
- **THEN** worktree-create が所属する親（workflow-setup）の calls に project-board-status-update が存在する

### Requirement: Orphan 削減検証

変更完了後、`loom orphans` の Isolated 件数が 10 件以下でなければならない（MUST）。
残存する Isolated は設計上の意図的な孤立であること（SHALL）。

#### Scenario: orphan 削減の検証
- **WHEN** 全ての calls 追加が完了し `loom orphans` を実行する
- **THEN** Isolated セクションの件数が 10 件以下である

#### Scenario: loom check/validate の継続 PASS
- **WHEN** deps.yaml の変更後に `loom check` と `loom validate` を実行する
- **THEN** 両方とも PASS（violations: 0、missing: 0）を返す

### Requirement: SVG エッジ数の増加

`loom update-readme` による SVG 再生成後、DOT グラフのエッジ数が変更前より増加していなければならない（MUST）。

#### Scenario: SVG 再生成
- **WHEN** `loom update-readme` を実行する
- **THEN** 生成された SVG/DOT のエッジ数がベースライン（変更前の記録値）より増加している
