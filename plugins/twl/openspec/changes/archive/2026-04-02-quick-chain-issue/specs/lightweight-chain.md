## ADDED Requirements

### Requirement: 軽量 chain 定義

deps.yaml の chains セクションに `quick-setup` chain を定義しなければならない（MUST）。軽量 chain は 7 ステップ以下で構成する。

#### Scenario: quick-setup chain の構成
- **WHEN** deps.yaml の chains セクションを参照する
- **THEN** `quick-setup` chain が以下のステップで定義されている: init, worktree-create, project-board-status-update

#### Scenario: 軽量 chain の merge-gate
- **WHEN** quick-setup chain で処理された PR がマージ準備完了となる
- **THEN** merge-gate が実行され、動的レビュアー構築で品質チェックが行われる（SHALL）

### Requirement: workflow-setup init quick ラベル検出

workflow-setup の init ステップは、Issue に `quick` ラベルが付与されている場合にそれを検出しなければならない（MUST）。

#### Scenario: quick ラベル付き Issue の検出
- **WHEN** init ステップが Issue 番号付きで実行され、その Issue に `quick` ラベルが付与されている
- **THEN** JSON 出力に `"is_quick": true` を含め、`recommended_action` は通常通り決定する

#### Scenario: quick ラベルなし Issue
- **WHEN** init ステップが Issue 番号付きで実行され、その Issue に `quick` ラベルがない
- **THEN** JSON 出力に `"is_quick": false` を含める（または `is_quick` フィールドを省略する）

#### Scenario: Issue 番号なしでの実行
- **WHEN** init ステップが Issue 番号なしで実行される
- **THEN** quick 検出は行わない。通常の判定ロジックのみ実行する（SHALL）

### Requirement: workflow-setup chain 分岐

workflow-setup SKILL.md は、init の `is_quick` 出力に基づき chain を分岐しなければならない（MUST）。

#### Scenario: quick chain への分岐
- **WHEN** init 出力の `is_quick` が `true`
- **THEN** quick-setup chain のステップのみを実行し、OpenSpec（opsx-propose, ac-extract）をスキップする。worktree 作成後は「直接実装可能」と案内する

#### Scenario: 通常 chain の維持
- **WHEN** init 出力の `is_quick` が `false` または未設定
- **THEN** 通常の setup chain を実行する（現行動作を維持）

## ADDED Requirements

### Requirement: quick GitHub ラベル作成

`quick` ラベルが対象リポジトリに存在しなければならない（MUST）。

#### Scenario: ラベルの存在確認
- **WHEN** co-issue が quick ラベル付きで Issue を作成しようとする
- **THEN** 対象リポジトリに `quick` ラベルが事前に存在する

### Requirement: 軽量 chain 後の PR 作成とマージ

軽量 chain で処理された Issue は、直接実装 → commit → push → PR 作成 → merge-gate の流れで完了しなければならない（SHALL）。

#### Scenario: 軽量 chain の完了フロー
- **WHEN** quick-setup chain が完了し、実装が終わった
- **THEN** workflow-test-ready の代わりに、直接 PR 作成と merge-gate を実行する

#### Scenario: merge-gate の品質保証
- **WHEN** 軽量 chain の PR が merge-gate に到達する
- **THEN** merge-gate は diff サイズに応じた動的レビュアーを構築し、通常と同等の品質基準で判定する（MUST）
