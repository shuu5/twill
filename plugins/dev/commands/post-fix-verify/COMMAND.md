# fix 後の軽量コードレビュー

fix-phase で修正されたコードの差分に対して軽量レビューを実行する。
fix が新たな問題を導入していないことを確認する。

## 入力

- fix-phase による変更差分（`git diff HEAD~1`）

## 出力

- 検証結果（PASS / WARN + findings）

## 実行ロジック（MUST）

### Step 1: fix 差分の取得

```bash
git diff HEAD~1 --name-only  # fix で変更されたファイル
git diff HEAD~1              # 差分内容
```

### Step 2: 軽量レビュー

fix 差分に対して以下を検証:

| チェック | 内容 |
|---------|------|
| 構文チェック | 変更ファイルの構文エラーがないこと |
| スコープ逸脱 | fix が元の finding のスコープを超えていないこと |
| 新規問題 | fix が新たな CRITICAL finding を導入していないこと |

### Step 3: 結果判定

```
IF 新規 CRITICAL finding なし → PASS
IF 新規 WARNING finding あり → WARN（続行可）
IF 新規 CRITICAL finding あり → FAIL（再 fix 必要）
```
