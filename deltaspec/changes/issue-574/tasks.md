## 1. SKILL.md 実装

- [x] 1.1 `plugins/twl/skills/workflow-issue-lifecycle/SKILL.md` を読み込み、Step 4 と Step 5 の間に Step 4.5 を挿入する
- [x] 1.2 Step 4.5 に `quick_flag=false` かつ `STATE != circuit_broken` の条件分岐を追加する
- [x] 1.3 条件を満たす場合に `labels_hint` へ `"refined"` を追記するロジックを記述する

## 2. bats テスト追加

- [x] 2.1 `plugins/twl/tests/bats/skills/workflow-issue-lifecycle.bats` を読み込み、既存テスト構造を確認する
- [x] 2.2 Step 4.5 正常完了ケース（`quick_flag=false`、`STATE` が `circuit_broken` でない）のテストケースを追加する
- [x] 2.3 Step 4.5 quick モードスキップケース（`quick_flag=true`）のテストケースを追加する
- [x] 2.4 Step 4.5 circuit_broken スキップケース（`STATE=circuit_broken`）のテストケースを追加する
