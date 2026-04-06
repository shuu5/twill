## Why

現行 workflow-setup は 9 ステップ中約 65% が機械的ルーティング（引数解析、条件分岐、Skill 呼び出し）であり、LLM 判断が必要な部分（arch-ref コンテキスト抽出、OpenSpec 提案生成）と混在している。deps.yaml v3.0 の chains セクションでステップ順序を宣言的に定義し、SKILL.md をドメインルール・ガードレールのみに縮小することで、chain-driven パターンの最初の実践例とする。

## What Changes

- deps.yaml に `chains` セクションを追加し、`setup` chain を定義する
- chain に参加する各コンポーネント（init, worktree-create, project-board-status-update, crg-auto-build, opsx-propose, workflow-test-ready）に `chain`, `step_in`, `calls` フィールドを追加する
- workflow-setup の SKILL.md を chain で表現できない判断ロジック（arch-ref 抽出、propose/apply/direct 分岐のドメインルール）のみに縮小する
- 不足するコンポーネント（init, worktree-create 等）を deps.yaml に追加する

## Capabilities

### New Capabilities

- **setup chain 定義**: deps.yaml chains セクションで setup ワークフローのステップ順序を宣言的に管理
- **chain generate 対応**: `loom chain generate setup --write` でチェックポイントテンプレートと called-by 宣言を自動生成可能
- **chain validate 対応**: `loom chain validate` で双方向参照整合性・ステップ順序を機械的に検証可能

### Modified Capabilities

- **workflow-setup SKILL.md 縮小**: 現行比 50%+ のトークン削減。chain で表現可能なステップ順序・ルーティングを排除し、ドメインルール（arch-ref 抽出ロジック、OpenSpec 分岐条件）のみに絞る
- **deps.yaml コンポーネント追加**: init, worktree-create, project-board-status-update, crg-auto-build 等を atomic として登録

## Impact

- **deps.yaml**: chains セクション追加、既存コンポーネントへの chain/step_in/calls フィールド追加、新規 atomic コンポーネント登録
- **SKILL.md**: workflow-setup の大幅縮小（機械的ステップの削除）
- **loom CLI 依存**: `loom chain generate` / `loom chain validate` が利用可能であること（loom#13 完了済み、loom#30 は --check/--all 拡張で必須ではない）
- **後続 Issue**: B-5（merge-gate chain）等の chain 定義の参考パターンとなる
