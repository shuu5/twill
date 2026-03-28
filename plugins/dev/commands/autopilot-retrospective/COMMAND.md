# Phase 振り返り

Phase 完了後に振り返りを実行し、成功/失敗パターンを分析する。
autopilot-phase-postprocess から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$P` | 現在の Phase 番号 |
| `$ISSUES` | Phase 内の全 Issue 番号リスト（スペース区切り） |
| `$SESSION_ID` | autopilot セッション ID |
| `$SESSION_STATE_FILE` | session.json のパス |
| `$PHASE_COUNT` | 総 Phase 数 |

## 出力変数

| 変数 | 説明 |
|------|------|
| `$PHASE_INSIGHTS` | 次 Phase 向け知見（最終 Phase では空） |

## 実行ロジック（MUST）

### Step 1: Phase 結果集約

各 Issue について state-read.sh で情報を収集:

```bash
for ISSUE in $ISSUES; do
  STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
  case "$STATUS" in
    done)
      PR=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field pr_number)
      # done Issue の PR 番号と変更ファイルを集約
      ;;
    failed)
      FAILURE=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field failure)
      # failure 情報を集約
      ;;
  esac
done
```

doobidoo から merge-gate decision 記録も取得:
```
mcp__doobidoo__memory_search(type=merge-gate-decision, session_id=$SESSION_ID)
```

### Step 2: パターン分析（LLM 推論）

- 成功パターン: 共通する成功要因
- 失敗パターン: 同種の失敗原因
- merge-gate finding の傾向

### Step 3: 次 Phase 向け知見の生成

- 失敗パターンの回避策
- 注意すべきファイル/モジュール
- 知見はワーカーの判断を制約しない「参考情報」

**最終 Phase の場合**: 振り返りは実行するが PHASE_INSIGHTS は空文字列とする。

### Step 4: doobidoo 保存

```
mcp__doobidoo__memory_store({
  content: "## Phase ${P} Retrospective (Session: ${SESSION_ID})\n**Results**: done=${DONE}, fail=${FAIL}, skipped=${SKIP}\n**Patterns**: ${PATTERN_SUMMARY}\n**Insights**: ${INSIGHTS}",
  metadata: { type: "phase-retrospective", session_id: "${SESSION_ID}", phase: ${P} }
})
```

### Step 5: session.json に追記

```bash
tmp=$(mktemp)
jq --arg phase "$P" --arg results "$RESULTS" --arg insights "$INSIGHTS" \
  '.retrospectives += [{"phase": ($phase | tonumber), "results": $results, "insights": $insights}]' \
  "$SESSION_STATE_FILE" > "$tmp" && mv "$tmp" "$SESSION_STATE_FILE"
```

## 禁止事項（MUST NOT）

- マーカーファイルを参照してはならない
- 最終 Phase で PHASE_INSIGHTS を生成してはならない（空文字列とする）
