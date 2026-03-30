# OpenSpec 実装ラッパー

`/dev:apply` をラップし、完了後に PR サイクルへの誘導を出力する。

## 引数

- `change-id`: OpenSpec change ID（省略時は自動検出）

## フロー制御（MUST）

### Step 1: change-id 解決

openspec/changes/ からディレクトリを検出。1 つ → 自動選択、複数 → 最新を自動選択。

### Step 2: apply 実行

`/dev:apply <change-id>` を Skill tool で実行。tasks.md に沿って実装を進める。

### Step 3: チェックポイント出力（MUST）

全タスク完了後:

- **`--auto` モード時**: 即座に `/dev:workflow-pr-cycle --spec <change-id>` を Skill tool で実行して chain を継続。停止するな。
- **通常時**: 以下を表示して停止。

```
>>> 実装完了: <change-id>

次のステップ:
  /dev:workflow-pr-cycle --spec <change-id> で PR サイクル開始
```

## 禁止事項（MUST NOT）

- tasks.md にないタスクを勝手に追加してはならない
