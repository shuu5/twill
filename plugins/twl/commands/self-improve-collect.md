---
type: atomic
tools: [Agent, Bash, Read]
effort: low
maxTurns: 10
---
# self-improve Issue 収集

`self-improve` ラベル付きGitHub Issueを収集し、構造化・分類・優先度ソートする。

## 実行フロー（MUST）

### Step 1: Issue一覧取得

```bash
gh issue list --label "self-improve" --state open --json number,title,body,labels,createdAt --limit 50
```

Issue が 0 件の場合は「改善候補Issueなし」と報告して終了。

### Step 2: Issueパース

各Issueの本文を `refs/self-improve-format.md` のテンプレートに基づきパースする。

#### フォーマット準拠Issue

以下のフィールドを抽出:

| フィールド | 抽出元 |
|-----------|--------|
| カテゴリ | `- **カテゴリ**: <value>` |
| 重複排除キー | `- **重複排除キー**: <value>` |
| 検出ソース | `- **検出ソース**: <value>` |
| 信頼度 | `- **信頼度**: <value>` |
| 検出根拠 | `## 検出根拠` セクション |
| 改善提案 | `## 改善提案` セクション |
| 対象specialist | `- 対象specialist: <value>` |

#### フォーマット非準拠Issue

- タイトルの `[Self-Improve] <category>:` からカテゴリを推定
- カテゴリが判別不能な場合は `process-inefficiency` をデフォルト設定
- 本文全体を改善提案として扱う
- 信頼度を 50 に設定

### Step 3: 関連コンポーネント特定

各Issueのカテゴリ・対象specialist・改善提案から、変更対象のdev pluginファイルパスを特定:

| カテゴリ | 対象specialist指定あり | 対象specialist指定なし |
|---------|----------------------|---------------------|
| `prompt-quality` | `agents/<specialist>.md` | 改善提案のファイルパス言及を検索 |
| `false-positive` | `agents/<specialist>.md` | 改善提案のファイルパス言及を検索 |
| `rule-gap` | — | `refs/baseline/` 配下を検索 |
| `autofix-repeat` | — | 改善提案のファイルパス言及を検索 |
| `process-inefficiency` | — | `commands/` or `skills/` 配下を検索 |

ファイルパス特定には以下を実行:
```bash
# 改善提案テキスト内のパス参照を検索
grep -oP '(commands|skills|agents|refs)/[a-z0-9_/-]+\.(md|sh)' <<< "$PROPOSAL_TEXT"
```

### Step 4: 優先度ソート

収集したIssueを以下の基準でソート:

1. **信頼度降順**（主キー）
2. **カテゴリ優先度**（副キー）:
   - prompt-quality: 1（最高）
   - rule-gap: 2
   - false-positive: 3
   - autofix-repeat: 4
   - process-inefficiency: 5（最低）

### Step 5: 結果出力

以下の形式で出力:

```markdown
## self-improve Issue 収集結果

| # | Issue | カテゴリ | 信頼度 | 対象コンポーネント |
|---|-------|---------|--------|-------------------|
| 1 | #N: タイトル | prompt-quality | 85 | agents/worker-security-reviewer.md |
| 2 | #M: タイトル | rule-gap | 72 | refs/baseline/ |

合計: N件
```

## 禁止事項（MUST NOT）

- Issue の修正・クローズを行ってはならない（状態読み取りのみ）
- 改善提案の生成を行ってはならない（self-improve-propose が担当）
