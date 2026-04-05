# OpenSpec アーカイブ

`/twl:archive` をラップし、delta specs を main specs に統合する。

## 引数

- `change-id`: OpenSpec change ID（省略時は自動検出）

## フロー制御（MUST）

### Step 1: change-id 解決

openspec/changes/ からディレクトリを検出。

### Step 1.5: delta spec sync

delta specs と main specs を比較し、変更内容を統合する。

### Step 2: CLI でアーカイブ実行

```bash
deltaspec archive "<change-id>" --yes --skip-specs
```

### Step 3: チェックポイント出力

```
>>> アーカイブ完了: <change-id>

次のステップ:
  /twl:worktree-delete で開発ブランチをクリーンアップ
```

## 禁止事項（MUST NOT）

- worktree-delete を自動実行してはならない（ユーザー確認が必要）
