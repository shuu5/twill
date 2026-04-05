## Why

`agents/issue-critic.md`（L62-69）と `agents/issue-feasibility.md`（L53-60）に同一内容の「調査バジェット制御（MUST）」セクションが重複しており、将来の変更時に同期漏れが生じるリスクがある（PR #189 レビューで検出）。

## What Changes

- `refs/ref-investigation-budget.md`（新規）を作成し、調査バジェット制御セクションの内容を移動
- `agents/issue-critic.md` の調査バジェット制御セクションを削除し、ref 参照指示に置換。frontmatter `skills:` に `ref-investigation-budget` を追加
- `agents/issue-feasibility.md` に同様の変更を適用
- `tests/scenarios/co-issue-specialist-maxturns-fix.test.sh` の assert を更新（agent 本文 → ref ファイルへの参照チェックに変更）
- `deps.yaml` の refs セクションと agent の skills フィールドを更新

## Capabilities

### New Capabilities

- `refs/ref-investigation-budget.md`: 調査バジェット制御ルールの共通 ref（issue-critic / issue-feasibility が参照）

### Modified Capabilities

- `agents/issue-critic.md`: 調査バジェット制御セクションを削除し、ref 参照指示に置換
- `agents/issue-feasibility.md`: 同上

## Impact

- **変更ファイル**: `refs/ref-investigation-budget.md`（新規）、`agents/issue-critic.md`、`agents/issue-feasibility.md`、`tests/scenarios/co-issue-specialist-maxturns-fix.test.sh`、`deps.yaml`
- **影響範囲**: issue-critic / issue-feasibility の起動フロー（調査バジェット制御ロジック自体は変更なし）
- **依存**: なし（既存 ref 機構を利用）
