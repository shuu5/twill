# self-improve 改善提案生成

self-improve-collect の収集結果を入力に、ECC知識と照合して具体的な改善提案を生成する。

## 引数

（なし）

## 前提

- self-improve-collect の結果（Issue一覧 + 関連コンポーネント）が会話コンテキストに存在すること

## 実行フロー（MUST）

### Step 1: cooldown判定

直近7日以内にマージされた self-improve PR で変更されたファイルを取得:

```bash
# 直近7日のself-improve関連PRを検索
SINCE_DATE=$(date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ')
gh pr list --state merged --label "self-improve" --json number,mergedAt --limit 20 | \
  jq --arg since "$SINCE_DATE" '[.[] | select(.mergedAt > $since)]'
```

マージ済みPRが見つかった場合、各PRの変更ファイルを個別取得:
```bash
gh pr view <pr_number> --json files -q '.files[].path'
```

各Issueの対象コンポーネントが cooldown 対象かチェック:
- 対象ファイルが直近マージ済みPRの変更ファイルに含まれる → cooldown としてスキップ
- スキップ理由を報告

### Step 2: ECC知識照合

最新のECCレポートを確認:

```bash
ls -t docs/ecc-analysis/updates/*.md 2>/dev/null | head -1
```

| 条件 | 動作 |
|------|------|
| レポートが存在し、30日以内 | レポートを Read して関連エントリを抽出 |
| レポートが存在しない or 30日超 | `/dev:ecc-monitor evaluate` を Skill tool で実行 |

ECC照合:
- 各Issueの対象コンポーネントに対応するECCカテゴリのエントリを抽出
- 「必須」「推奨」評価のエントリを改善提案に統合

### Step 3: 改善提案生成

各Issueについて、以下の情報を統合して具体的な改善案を生成:

1. **対象ファイルを Read** して現在の内容を把握
2. **Issue の検出根拠・改善提案** を分析
3. **ECC知識**（存在する場合）を参照

#### カテゴリ別の提案生成ルール

| カテゴリ | 提案内容 |
|---------|---------|
| `prompt-quality` | specialist プロンプトに追加すべき検出パターン・ルールをdiff形式で提示 |
| `rule-gap` | 新規 baseline 定義のドラフトを生成し、配置先パスを指定 |
| `false-positive` | specialist プロンプトに除外条件・例外ルールの追加案を提示 |
| `autofix-repeat` | autofix-loop のパターンDB追加 or baseline ルール追加を提案 |
| `process-inefficiency` | 対象コマンド/スキルの改善案を提示 |

### Step 4: 提案出力

各Issueについて以下の形式で出力:

```markdown
### Issue #N: <タイトル>

**カテゴリ**: <category>
**信頼度**: <confidence>
**対象ファイル**: <file_path>
**ECC関連知識**: あり/なし

#### 改善案

<具体的な修正内容。diff形式または新規ファイルのドラフト>

#### 変更の影響

<変更による影響範囲の説明>
```

### Step 5: ユーザー確認

autopilot 判定（ISSUE_NUM はブランチ名から抽出）:
```bash
ISSUE_NUM=$(git branch --show-current | grep -oP '^\w+/\K\d+(?=-)' 2>/dev/null || echo "")
IS_AUTOPILOT=false
if [ -n "$ISSUE_NUM" ]; then
  AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
  IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
fi
```

| 判定 | 動作 |
|------|------|
| IS_AUTOPILOT=true | 信頼度70以上の全Issueを自動承認 |
| IS_AUTOPILOT=false | 各Issueについて承認/棄却を確認 |

承認結果を記録:
- **承認**: 適用対象リストに追加
- **棄却**: Issue にコメント追加（`gh issue comment #N --body "棄却理由: <reason>"`）

### Step 6: 結果出力

```markdown
## 改善提案結果

| # | Issue | 状態 | 理由 |
|---|-------|------|------|
| 1 | #N | 承認 | — |
| 2 | #M | cooldown | 直近PR #K で変更済み |
| 3 | #L | 棄却 | ユーザー判断 |

承認済み: N件（次のステップで適用）
```

## 禁止事項（MUST NOT）

- ユーザー確認なしでファイルを変更してはならない（IS_AUTOPILOT=true 時を除く）
- cooldown 判定をスキップしてはならない
- ECC知識がない場合にエラー終了してはならない（Issue情報のみで提案を生成）
