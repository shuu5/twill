## MODIFIED Requirements

### Requirement: co-issue 推奨ラベル受け渡しチェーン

co-issue は Phase 3 で issue-structure が出力した推奨ラベル（`## 推奨ラベル` セクション）を抽出し、Phase 4 の issue-create に `--label` 引数として渡さなければならない（SHALL）。

#### Scenario: 推奨ラベルあり時のラベル自動付与
- **WHEN** issue-structure が `## 推奨ラベル` セクションに `ctx/workflow` を出力する
- **THEN** co-issue は `ctx/workflow` を抽出し、issue-create の `--label ctx/workflow` 引数に含める

#### Scenario: 推奨ラベルなし時のスキップ
- **WHEN** issue-structure の出力に `## 推奨ラベル` セクションが存在しない
- **THEN** co-issue は `--label` 引数を付与せず issue-create を呼び出す

#### Scenario: 複数 Issue 一括作成時のラベル個別適用
- **WHEN** Phase 2 で複数 Issue に分解され、各 issue-structure が異なる ctx/* ラベルを出力する
- **THEN** 各 Issue に対応する推奨ラベルが個別に issue-create の `--label` 引数に渡される
