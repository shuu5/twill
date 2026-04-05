# Visual 検証（chain-driven）

E2E テストと Visual スクリーニングを管理する。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 6 | e2e-screening（本コンポーネント） | composite |

## ドメインルール

### 発動条件

```
IF E2E テストファイルが存在（tests/e2e/*.spec.ts）
THEN E2E テストを実行
ELSE スキップ（PASS を返す）
```

### 実行フロー

1. E2E テスト実行（Playwright）
2. Visual diff 検出（スクリーンショット比較、設定されている場合）
3. 失敗テストの自動修復試行（e2e-heal）

### 結果判定

| 条件 | 判定 |
|------|------|
| 全テスト PASS | PASS |
| 修復後に全テスト PASS | PASS（修復ログ付き） |
| 修復不可のテスト FAIL | FAIL |
| E2E テストなし | PASS（スキップ） |

## チェックポイント（MUST）

`/dev:pr-cycle-report` を Skill tool で自動実行。

