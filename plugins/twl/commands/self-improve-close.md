---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 10
---
# self-improve Issue クローズ

改善PRのマージ結果に基づき、対応するself-improve Issueにコメントを追加してクローズする。

## 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| `issue_number` | Yes | クローズ対象のIssue番号 |
| `pr_number` | Yes | 対応するPR番号 |
| `summary` | Yes | 変更内容サマリー |
| `--rejected` | No | PR却下時フラグ（後続に理由を指定） |

## 実行フロー（MUST）

### Step 1: 引数解析

会話コンテキストから以下を取得:
- `ISSUE_NUMBER`: Issue番号
- `PR_NUMBER`: PR番号
- `SUMMARY`: 変更内容サマリー
- `REJECTED`: 却下フラグ（true/false）
- `REASON`: 却下理由（rejected時のみ）

### Step 2: 分岐処理

#### 正常系（REJECTED=false）

```bash
# PRマージ（失敗時は処理を中断しエラーを返す）
gh pr merge "${PR_NUMBER}" --squash --delete-branch || {
  echo "ERROR: PR #${PR_NUMBER} のマージに失敗しました" >&2
  exit 1
}

# コメント本文をファイル経由で渡す（インジェクション防止）
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
cat > "${TMPDIR}/comment.md" <<COMMENT_EOF
## 改善適用完了

- **適用PR**: #${PR_NUMBER}
- **変更内容**: ${SUMMARY}

### 検証ポイント
次回の実セッションで以下を確認:
- <検証項目1>
- <検証項目2>
COMMENT_EOF

gh issue comment "${ISSUE_NUMBER}" --body-file "${TMPDIR}/comment.md"

# Issueクローズ
gh issue close "${ISSUE_NUMBER}"
```

検証ポイントは `SUMMARY` の内容から適切な確認項目を生成する。

#### 却下系（REJECTED=true）

```bash
# コメント本文をファイル経由で渡す（インジェクション防止）
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
printf '改善PR #%s が却下されました。理由: %s' "${PR_NUMBER}" "${REASON}" > "${TMPDIR}/comment.md"

gh issue comment "${ISSUE_NUMBER}" --body-file "${TMPDIR}/comment.md"
```

Issueはopenのまま残す。

### Step 3: 結果出力

```markdown
| 項目 | 値 |
|------|-----|
| Issue | #<ISSUE_NUMBER> |
| PR | #<PR_NUMBER> |
| 結果 | クローズ完了 / 却下記録 |
```

## 禁止事項（MUST NOT）

- 引数なしで実行してはならない（issue_number, pr_number, summary は必須）
- 却下時にIssueをクローズしてはならない
