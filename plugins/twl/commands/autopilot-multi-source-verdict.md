---
type: atomic
tools: [Bash, Read, mcp__doobidoo__memory_search]
effort: medium
maxTurns: 30
---
# Multi-Source Verdict (atomic)

multi-source 統合 LLM 判断 atomic。単一 specialist (#135 worker-issue-pr-alignment) では判定不能な「PR diff 軽量だが正当」ケースを Pilot LLM が統合判断する。

## 入力

| 変数 | 説明 |
|------|------|
| `$PR_NUM` | PR 番号 |
| `$ISSUE_NUM` | Issue 番号 |

## opt-out

```bash
if [ "${PILOT_ACTIVE_REVIEW_DISABLE:-0}" = "1" ]; then
  echo "WARN: PILOT_ACTIVE_REVIEW_DISABLE=1 — autopilot-multi-source-verdict をスキップ" >&2
  echo '{"verdict":"skipped","confidence":0,"reason":"PILOT_ACTIVE_REVIEW_DISABLE=1"}'
  exit 0
fi
```

## 処理ロジック (MUST)

### Step 1: ソース収集 (各最大 1KB / 100 行に制限)

5 種のソースを収集する:

```bash
# ソース 1: PR メタ + body verdict
PR_META=$(gh pr view "$PR_NUM" --json title,body,additions,deletions 2>/dev/null | head -c 1024 || echo "{}")

# ソース 2: PR commit history
COMMIT_LOG=$(git log --oneline origin/main..HEAD 2>/dev/null | head -100 || echo "")

# ソース 3: Issue + 直近 5 comment
ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --json title,body,comments 2>/dev/null | jq '{title:.title, body:(.body[:1024]), comments:(.comments[-5:][:][:.body[:1024]])}' || echo "{}")

# ソース 4: audit-history (doobidoo memory_search)
# doobidoo MCP server 利用不可時のフォールバック: 空として扱い verdict: uncertain を返す
AUDIT_HISTORY=""  # mcp__doobidoo__memory_search で取得 (hybrid mode, 最大 3 件)

# ソース 5: worker-issue-pr-alignment specialist 結果 (存在する場合)
ALIGNMENT_RESULT=""  # PR comments / review から引用
```

**ソース 4 (audit-history) の取得**:

```
mcp__doobidoo__memory_search({
  query: "merge-gate decision session audit issue ${ISSUE_NUM}",
  mode: "hybrid",
  quality_boost: 0.3,
  limit: 3
})
```

doobidoo MCP server が利用不可の場合、ソース 4 を空として扱い、最終 verdict は `uncertain` とする。

### Step 2: LLM 統合判断

LLM が以下の基準で「軽量 diff の正当性」を判定する:

1. **main 状態との矛盾**: PR diff が main の既存コードと整合するか
2. **Worker follow-up Issue の具体性**: 実 spawn 証拠があるか
3. **PR body verdict 内訳の現実性**: PASS/WARN/FAIL の分布が妥当か
4. **audit-history の整合性**: stale=0 / 未レビュー=0 か

### Step 3: verdict 出力

```json
{
  "verdict": "legitimate-light | suspicious-trivial | uncertain",
  "confidence": 0-75,
  "sources": {
    "pr_meta": "<逐語引用>",
    "commit_log": "<逐語引用>",
    "issue_data": "<逐語引用>",
    "audit_history": "<逐語引用>",
    "alignment_result": "<逐語引用>"
  },
  "reasoning": "<判定理由>"
}
```

## 出力仕様 (MUST)

- `verdict`: `legitimate-light` | `suspicious-trivial` | `uncertain` の 3 値
- `confidence`: 0-75 (上限 75、#135 alignment specialist と整合。LLM 単独判断のため)
- 各ソースの **逐語引用** を `sources` に含める (MUST)
- **引用なしの判定は parser が WARNING に降格** (hallucination 対策)

## Auto-decision 閾値

- `confidence >= 75 && verdict == legitimate-light` → Pilot 用 auto-decision 許可
- それ以外 → Pilot ユーザー判断にエスカレーション

## 禁止事項 (MUST NOT)

- confidence を 75 より大きく設定してはならない
- 逐語引用なしで verdict を出力してはならない
- PR diff 全文を読んではならない (ソース 1 の PR メタのみ)
- 各ソースの 1KB / 100 行制限を超えてはならない
