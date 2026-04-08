---
type: atomic
tools: [Bash, Skill, Read]
effort: low
maxTurns: 10
---
# TypeScript 機械的検証

TypeScript プロジェクトの型チェック・lint・ビルドを機械的に実行する。
非 TypeScript プロジェクトではスキップする。

## 入力

- PR ブランチのソースコード

## 出力

- 検証結果（PASS / FAIL + エラーリスト）

## 冪等性

何度実行しても同じ結果を返す（副作用なし）。

## 実行ロジック（MUST）

### Step 1: TypeScript プロジェクト判定

```
IF tsconfig.json が存在しない → PASS を返してスキップ
```

### Step 2: 型チェック + lint 実行

| チェック | コマンド | 失敗時 |
|---------|---------|--------|
| 型チェック | `npx tsc --noEmit` | FAIL + エラー行を出力 |
| lint | `npx eslint .` （.eslintrc 存在時のみ） | FAIL + 違反を出力 |
| ビルド | `npm run build` （build スクリプト存在時のみ） | FAIL + エラーを出力 |

### Step 3: 結果判定

```
IF 全チェック PASS → PASS
ELSE → FAIL（最初のエラーで停止せず全チェックを実行）
```

## チェックポイント（MUST）

`/twl:phase-review` を Skill tool で自動実行。

