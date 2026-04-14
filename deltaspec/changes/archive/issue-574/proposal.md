## Why

`workflow-issue-lifecycle` において、spec-review の round loop が正常完了した Issue に `refined` ラベルが付与されない。`refined` ラベルは「specialist レビューによる品質保証が完了した Issue」を示すマーカーであり、autopilot が実装対象 Issue を選択する際の品質フィルタとして機能するため、付与漏れが発生すると品質保証済み Issue が autopilot に認識されないという問題が生じる。

## What Changes

- `plugins/twl/skills/workflow-issue-lifecycle/SKILL.md` の Step 4（round loop）と Step 5（arch-drift）の間に Step 4.5（refined ラベル判定）を追加
- Step 4.5: `quick_flag=false` かつ round loop が `circuit_broken` でない正常完了時に `labels_hint` へ `"refined"` を追加するロジックを挿入
- `plugins/twl/tests/bats/skills/workflow-issue-lifecycle.bats` に Step 4.5 の判定ロジックを検証するテストケースを追加

## Capabilities

### New Capabilities

- `workflow-issue-lifecycle` が spec-review round loop の正常完了後に自動的に `refined` ラベルを `labels_hint` へ追記する

### Modified Capabilities

- `workflow-issue-lifecycle` SKILL.md のステップ順（Step 4.5 を新規挿入）
- `issue-create` 呼び出し前の `labels_hint` に `"refined"` が含まれる状態になる

## Impact

- `plugins/twl/skills/workflow-issue-lifecycle/SKILL.md`: Step 4.5 挿入（`quick_flag` と `circuit_broken` 状態による条件分岐）
- `plugins/twl/tests/bats/skills/workflow-issue-lifecycle.bats`: Step 4.5 用テストケース追加
- `issue-create.md` / `issue-cross-repo-create.md` への変更なし（方法 A 採用、方法 B 非採用）
- `refined` ラベルが存在しないリポジトリでも `gh issue create --label` は自動作成するためエラー非伝搬
