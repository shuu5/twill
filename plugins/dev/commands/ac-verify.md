# AC 検証（テスト結果と AC の照合）

## Context (auto-injected)
- Issue: !`source "$(git rev-parse --show-toplevel)/scripts/resolve-issue-num.sh" 2>/dev/null || true; resolve_issue_num 2>/dev/null || echo ""`

テスト結果とレビュー結果を Issue の受け入れ基準（AC）と照合し、
達成状況をマッピングして Issue コメントとして投稿する。

## 入力

- AC チェックリスト（ac-extract の出力）
- テスト結果（pr-test の出力）
- レビュー結果（phase-review の出力）

## 出力

- AC マッピング結果（各 AC の達成/未達成）
- Issue コメント

## 実行ロジック（MUST）

### Step 1: AC とテスト結果の照合

各 AC 項目について:

| 条件 | 判定 |
|------|------|
| 対応するテストが PASS | 達成 |
| 対応するテストが FAIL | 未達成 |
| 対応するテストなし | 手動確認要 |

### Step 2: Issue コメント投稿

```markdown
## AC 検証結果

- [x] AC1: deps.yaml chains に pr-cycle chain が定義されている
- [x] AC2: `twl chain validate` が pass する
- [ ] AC3: merge-gate が動的レビュアー構築で単一パスに統合されている
```

```bash
gh issue comment ${ISSUE_NUM} --body "${AC_REPORT}"
```
