---
tools: [mcp__doobidoo__memory_search]
---

# PR-cycle パターン分析

PR-cycle 完了後のセッションスナップショットを分析し、dev plugin の改善機会を検出する。
4 カテゴリ分析 → 重複排除 → self-improve Issue 自動起票 → doobidoo キャッシュ保存。

本コマンドの失敗は PR-cycle の成否に影響しない（SHALL NOT）。

## 引数

- `--auto`: 人間承認スキップで自動起票
- `--snapshot-dir <path>`: セッションスナップショットのディレクトリ（省略時は最新を自動検出）

## 入力データ

セッションスナップショット（`${SNAPSHOT_DIR}/`）から以下を読み取る:

| ファイル | 用途 |
|---------|------|
| `03-review-result.md` | レビュー結果 |
| `03.5-in-scope.md` | スコープ内 findings |
| `03.5-out-of-scope.md` | スコープ外 findings |
| `04-test-result.md` | テスト結果 |
| `06-fix-result.md` | fix 結果（存在時のみ） |
| `06.7-warning-fix-result.md` | warning fix 結果（存在時のみ） |

## 実行フロー

### Step 1: スナップショット取得

```bash
if [ -z "${SNAPSHOT_DIR}" ]; then
  SNAPSHOT_DIR=$(find /tmp -maxdepth 1 -name 'dev-pr-cycle-*' -type d -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)
fi
```

### Step 2: 4 カテゴリ分析

#### prompt-quality

specialist が検出すべきだった問題を特定。修正結果で修正されたが specialist から報告がなかったパターン。

#### rule-gap

レビュー結果で同一パターンの指摘が複数ファイルで繰り返され、`refs/baseline/` に対応ルールがないパターン。

#### false-positive

in-scope findings のうち fix-phase で修正対象にならなかったパターン。

#### autofix-repeat

fix 結果に同一パターンへの反復修正が記録されているパターン。

### Step 3: 重複排除

```
1. DEDUP_KEY = "${category}:${PATTERN_HASH}"
2. mcp__doobidoo__memory_search(query=DEDUP_KEY, mode="exact", limit=1)
3. gh issue list --label "self-improve" --search "${DEDUP_KEY}"
```

### Step 4: Issue 起票

信頼度 70 以上 + 重複なし → `self-improve` ラベル付きで Issue 起票。

### Step 5: doobidoo キャッシュ保存

全パターン（起票・非起票問わず）を doobidoo に保存。

### Step 6: 結果出力

`${SNAPSHOT_DIR}/07.3-pattern-analysis.md` に結果を書き込む。

## エラー処理

| エラー | 動作 |
|-------|------|
| スナップショット不在 | 警告 + 空結果で終了 |
| doobidoo 接続失敗 | 警告 + GitHub 検索のみで重複チェック |
| GitHub API 失敗 | 警告 + Issue 起票スキップ |
| 個別分析エラー | 該当カテゴリスキップ + 他は継続 |

## チェックポイント（MUST）

`/dev:all-pass-check` を Skill tool で自動実行。

