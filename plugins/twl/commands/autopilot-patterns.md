---
tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search]
---

# パターン検出

セッション状態から繰り返しパターンを検出し、self-improve Issue 起票を判定する。
autopilot-phase-postprocess から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$SESSION_ID` | autopilot セッション ID |
| `$SESSION_STATE_FILE` | session.json のパス |

## 実行ロジック（MUST）

### Step 1: merge-gate decision からパターン検出

```
mcp__doobidoo__memory_search(type=merge-gate-decision, session_id=$SESSION_ID)
```

finding の category/message をグルーピングし、count >= 2 のパターンを抽出。

### Step 2: failed Issue からパターン検出

state-read.sh で failed Issue の failure 情報を取得:

```bash
# .autopilot/issues/ の全 issue-*.json を走査
for ISSUE_FILE in "$AUTOPILOT_DIR"/issues/issue-*.json; do
  ISSUE_NUM=$(basename "$ISSUE_FILE" | grep -oP '\d+')
  STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE_NUM" --field status)
  if [ "$STATUS" = "failed" ]; then
    FAILURE=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE_NUM" --field failure)
    REASON=$(echo "$FAILURE" | jq -r '.message // "unknown"')
    # reason をグルーピング
  fi
done
```

同一 reason が 2 回以上 → パターンとして記録。

### Step 3: doobidoo 保存

```
mcp__doobidoo__memory_store({
  content: "## Session Patterns (Session: ${SESSION_ID})\n**Tech-debt patterns**: ${TECH_DEBT_PATTERNS}\n**Failure patterns**: ${FAILURE_PATTERNS}",
  metadata: { type: "session-pattern", session_id: "${SESSION_ID}" }
})
```

### Step 4: self-improve Issue 起票判定

```
IF パターンの confidence >= 80 AND count >= 2:
  # PATTERN_TITLE サニタイズ（MUST）
  SAFE_TITLE=$(echo "$PATTERN_TITLE" | tr -cd 'a-zA-Z0-9 _-')

  gh issue create -R "shuu5/ubuntu-note-system" \
    --title "[Self-Improve] ${SAFE_TITLE}" \
    --label "self-improve" \
    --body-file "/tmp/self-improve-pattern-${SESSION_ID}.md"

  # session.json に記録
  tmp=$(mktemp)
  jq --arg url "$ISSUE_URL" --arg title "$SAFE_TITLE" \
    '.self_improve_issues += [{"url": $url, "title": $title}]' \
    "$SESSION_STATE_FILE" > "$tmp" && mv "$tmp" "$SESSION_STATE_FILE"
ELSE:
  # doobidoo キャッシュにのみ記録
```

## 禁止事項（MUST NOT）

- マーカーファイル (.fail) を参照してはならない（state-read で failure 取得）
- PATTERN_TITLE のサニタイズをスキップしてはならない
- confidence < 80 で Issue を起票してはならない
