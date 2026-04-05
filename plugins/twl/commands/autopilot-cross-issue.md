# Cross-issue 影響分析

完了 Issue の変更ファイルと後続 Phase の Issue スコープを比較し、ファイル競合リスクを検出する。
session-add-warning.sh 経由で session.json に警告を追記。
autopilot-phase-postprocess から呼び出される（最終 Phase 以外）。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$SESSION_STATE_FILE` | session.json のパス |
| `$NEXT_PHASE_ISSUES` | 次 Phase の Issue 番号リスト（スペース区切り） |

## 出力変数

| 変数 | 説明 |
|------|------|
| `$CROSS_ISSUE_WARNINGS` | 連想配列（Issue番号→警告メッセージ、改行区切り） |

## 実行条件

最終 Phase では実行しない（後続 Phase が存在しないため）。

## 実行ロジック（MUST）

### Step 1: 完了 Issue の変更ファイル取得

```bash
# session.json から completed_issues の変更ファイルリストを取得
COMPLETED=$(jq -r '.completed_issues | to_entries[] | select(.value.files) | .key' "$SESSION_STATE_FILE")
```

### Step 2: 後続 Issue の body 取得

```bash
for ISSUE in $NEXT_PHASE_ISSUES; do
  BODY=$(gh issue view "$ISSUE" --json body -q '.body')
  COMMENTS=$(gh api "repos/{owner}/{repo}/issues/${ISSUE}/comments" --jq '[.[].body] | join("\n---\n")' 2>/dev/null || true)
done
```

### Step 3: 影響検出（LLM 推論）

```
FOR each next_issue in NEXT_PHASE_ISSUES:
  FOR each completed_issue in completed_issues:
    - ファイル名完全一致 → confidence: "high"
    - ディレクトリレベル一致 → confidence: "medium"
    - 意味的関連（LLM 判断） → confidence: "low"
```

### Step 4: session-add-warning.sh で session.json に追記

```bash
for ISSUE in $NEXT_PHASE_ISSUES; do
  if [ -n "${WARNING_MSG}" ]; then
    bash $SCRIPTS_ROOT/session-add-warning.sh --issue "$ISSUE" --warning "$WARNING_MSG"
  fi
done
```

### Step 5: CROSS_ISSUE_WARNINGS 構築

```bash
declare -A CROSS_ISSUE_WARNINGS
for ISSUE in $NEXT_PHASE_ISSUES; do
  WARNINGS=$(bash $SCRIPTS_ROOT/state-read.sh --type session --field "cross_issue_warnings" | \
    jq -r ".[] | select(.issue == \"$ISSUE\") | .warning")
  if [ -n "$WARNINGS" ]; then
    CROSS_ISSUE_WARNINGS[$ISSUE]="$WARNINGS"
  fi
done
```

high confidence 警告のみ Worker 起動プロンプトに注入する（autopilot-launch が参照）。

変更ファイルと後続 Issue のスコープに重複がない場合、CROSS_ISSUE_WARNINGS は空で session.json に警告は追記されない。

## 禁止事項（MUST NOT）

- session.json を直接編集してはならない（session-add-warning.sh に委譲）
- 最終 Phase で実行してはならない
- マーカーファイルを参照してはならない
