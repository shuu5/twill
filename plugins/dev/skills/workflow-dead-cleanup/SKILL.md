# Dead Component 削除 Workflow

## フロー制御（MUST）

### Step 1: 検出

`/dev:dead-component-detect` を実行。0件なら正常終了。

### Step 2: ユーザー選択

AskUserQuestion で削除対象を選択:
- **全て削除**: 外部参照なしコンポーネント全て
- **個別選択**: 番号をカンマ区切りで指定
- **スキップ**: 削除せず終了

外部参照ありが選択された場合 → 警告表示し再確認。

### Step 3: 削除実行

選択結果を `/dev:dead-component-execute` に渡して実行。
