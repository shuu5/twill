# スコープ判定 + Deferred Issue 作成

レビュー結果の finding を PR 変更ファイルと照合し、スコープ内/外に分離する。
スコープ外の High/Critical finding は Deferred Issue として自動作成する。

## 入力

- レビュー結果（findings リスト）
- PR 変更ファイルリスト（`git diff --name-only origin/main`）

## 出力

- スコープ内 findings（修正対象）
- スコープ外 findings（Deferred Issue として起票）

## 実行ロジック（MUST）

### Step 1: スコープ判定

各 finding の `file` フィールドを PR 変更ファイルリストと照合:

| 条件 | 判定 |
|------|------|
| finding.file が変更ファイルに含まれる | スコープ内 |
| finding.file が変更ファイルに含まれない | スコープ外 |

### Step 2: Deferred Issue 作成

スコープ外かつ `severity in [CRITICAL, WARNING]` の finding について:

```
gh issue create --title "tech-debt: ${finding.message}" \
  --body "## 検出元\nPR #${PR_NUM} のレビューで検出\n\n## 詳細\n${finding}" \
  --label "tech-debt"
```

### Step 3: 結果報告

スコープ内/外の件数と、作成した Deferred Issue のリンクを返す。
