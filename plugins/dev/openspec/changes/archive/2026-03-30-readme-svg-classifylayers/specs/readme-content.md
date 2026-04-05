## ADDED Requirements

### Requirement: プラグイン概要セクション
README.md の冒頭にプラグインの概要と設計哲学（chain-driven + autopilot-first）を記載しなければならない（SHALL）。

#### Scenario: README冒頭に概要が表示される
- **WHEN** README.md を開いたとき
- **THEN** プラグイン名、説明、設計哲学が最初に表示される

### Requirement: エントリーポイント表
README.md に 4 controllers（co-autopilot, co-issue, co-project, co-architect）と 5 workflows のエントリーポイント表を記載しなければならない（SHALL）。

#### Scenario: エントリーポイント表にcontrollersが含まれる
- **WHEN** README.md のエントリーポイント表を確認したとき
- **THEN** co-autopilot, co-issue, co-project, co-architect の4つのcontrollerとその役割が記載されている

#### Scenario: エントリーポイント表にworkflowsが含まれる
- **WHEN** README.md のエントリーポイント表を確認したとき
- **THEN** workflow-setup, workflow-test-ready, workflow-pr-cycle, workflow-dead-cleanup, workflow-tech-debt-triage の5つのworkflowが記載されている

### Requirement: コンポーネント数テーブル
README.md に skills, commands, agents, refs, scripts の各カテゴリのコンポーネント数テーブルを記載しなければならない（MUST）。

#### Scenario: コンポーネント数が正確に表示される
- **WHEN** README.md のコンポーネント数テーブルを確認したとき
- **THEN** deps.yaml から取得した実際のコンポーネント数が表示されている

### Requirement: 基本的な使い方セクション
README.md に基本的な使い方（主要コマンドの実行例）を記載しなければならない（SHALL）。

#### Scenario: 使い方に主要フローが記載されている
- **WHEN** README.md の使い方セクションを確認したとき
- **THEN** Issue起点の開発フロー（setup → apply → pr-cycle）の基本的な手順が記載されている

## MODIFIED Requirements

### Requirement: SVG グラフ再生成
`loom update-readme` を実行し、classify_layers v3.0 対応後の全コンポーネントが反映された SVG を生成しなければならない（MUST）。

#### Scenario: SVG に全コマンドが表示される
- **WHEN** `loom update-readme` を実行した後
- **THEN** docs/deps.svg に全87コマンドが表示されている

#### Scenario: SVG の orphan ノードが妥当
- **WHEN** SVG を確認したとき
- **THEN** orphan ノードはユーザー直接呼び出し可能なコマンド（init等）のみである
