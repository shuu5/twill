---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 10
---
# observe-retrospective: 過去の observation を集約しパターン抽出

## 引数

- `--session-id <id>` (必須): 対象セッション ID
- `--limit <N>` (optional, default: 5): 過去セッション検索数上限

## 処理フロー (MUST)

### Step 1: 現セッション結果読み込み

`.observation/<session_id>/aggregated.json` を Read。
ファイル不在の場合はエラー終了。

### Step 2: 過去結果検索

`mcp__doobidoo__memory_search` で過去の observation 結果を検索:

```
query: "observation detection pattern"
mode: hybrid
quality_boost: 0.3
limit: <N>
```

### Step 3: マージとパターン抽出

現セッション結果と過去の memory 結果を統合し:

1. **共通パターン** (>= 2 セッションで出現): `common_patterns` に分類
2. **新規パターン** (今回初出): `new_patterns` に分類
3. **Issue 起票候補**: severity=critical かつ共通パターンを `issue_draft_candidates` に分類

### Step 4: JSON 出力

```json
{
  "session_id": "<id>",
  "common_patterns": [
    {
      "pattern": "MergeGateError:",
      "occurrences": 3,
      "sessions": ["session-1", "session-2", "session-3"]
    }
  ],
  "new_patterns": [
    {
      "pattern": "silent.*deletion",
      "severity": "critical",
      "first_seen": "<timestamp>"
    }
  ],
  "issue_draft_candidates": [
    {
      "pattern": "MergeGateError:",
      "severity": "critical",
      "reason": "3 セッションで繰り返し検出"
    }
  ]
}
```

## 禁止事項 (MUST NOT)

- aggregated.json を改変しない (読み取り専用)
- memory_search の結果を鵜呑みにしない (現セッションとのクロス検証必須)
- Issue を直接起票しない (候補提示のみ、起票は controller の責務)
