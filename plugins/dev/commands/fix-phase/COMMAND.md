# 自動修正ループ（chain-driven）

CRITICAL finding の自動修正と再検証を管理する。
chain ステップの実行順序は deps.yaml で宣言されている。
本 COMMAND.md には chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 4 | fix-phase（本コンポーネント） | composite |

## ドメインルール

### 発動条件

```
IF phase-review の findings に severity=CRITICAL かつ confidence>=80 が存在
THEN fix-phase を実行
ELSE スキップ
```

### 修正ループ

1. CRITICAL findings を修正指示として渡す
2. コード修正を実施
3. 修正後にテスト再実行（pr-test）
4. テスト PASS → post-fix-verify へ
5. テスト FAIL → 修正を見直し再試行（最大 1 ループ）

### エスカレーション条件

```
IF 修正ループが 1 回を超える（自動修正で解決不可）
THEN fix-phase を中断し FAIL を返す
```

### 制約

- fix-phase 内での修正はスコープ内ファイルのみ
- 修正が他のテストを破壊する場合は即座に revert
- AI が判断に迷う場合は修正を試みず FAIL を返す
