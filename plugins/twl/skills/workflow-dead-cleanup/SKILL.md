---
name: dev:workflow-dead-cleanup
description: |
  不要コンポーネントの検出と削除。

  Use when user: says 不要コンポーネント削除/dead cleanup/デッドコード,
  or when called from tech-debt-triage.
type: workflow
effort: low
spawnable_by:
- user
---

# Dead Component 削除 Workflow

## フロー制御（MUST）

### Step 1: 検出

`/twl:dead-component-detect` を実行。0件なら正常終了。

### Step 2: ユーザー選択

AskUserQuestion で削除対象を選択:
- **全て削除**: 外部参照なしコンポーネント全て
- **個別選択**: 番号をカンマ区切りで指定
- **スキップ**: 削除せず終了

外部参照ありが選択された場合 → 警告表示し再確認。

### Step 3: 削除実行

選択結果を `/twl:dead-component-execute` に渡して実行。
