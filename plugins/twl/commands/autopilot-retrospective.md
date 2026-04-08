---
tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search, Bash, Read]
type: atomic
effort: medium
maxTurns: 30
---

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
| `$CHANGED_FILES` | Step 1 で done Issue の PR から収集した変更ファイルリスト（スペース区切り、Step 4.5 で使用） |

## 出力変数

| 変数 | 説明 |
|------|------|
| `$PHASE_INSIGHTS` | 次 Phase 向け知見（最終 Phase では空） |

## 実行ロジック（MUST）

### Step 1: Phase 結果集約

各 Issue について state-read.sh で情報を収集:

```bash
CHANGED_FILES=""
for ISSUE in $ISSUES; do
  STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
  case "$STATUS" in
    done)
      PR=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field pr_number)
      # done Issue の PR 番号と変更ファイルを集約。CHANGED_FILES に追記
      FILES=$(gh pr view "$PR" --json files -q '.files[].path' 2>/dev/null || true)
      CHANGED_FILES="${CHANGED_FILES} ${FILES}"
      ;;
    failed)
      FAILURE=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field failure)
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

### Step 3: 次 Phase 向け知見の生成（強度勾配付き）

知見は強度別 (info/warning/must) に分類される。各知見には文字列プレフィックスを付与する:

- `[info]`: ワーカーの判断を制約しない参考情報（デフォルト）
- `[warning]`: 注意喚起（特定ファイル/モジュールへの警告）
- `[must]`: **同種失敗パターン 2 回以上検出時のみ** 昇格される。Worker prompt の MUST 要件セクションに直接注入される

生成する知見:
- 失敗パターンの回避策
- 注意すべきファイル/モジュール
- 同種失敗パターンのカウント（Step 2 のパターン分析結果と session.json の `patterns` を照合）

**`must` 昇格条件 (MUST)**: 同種の失敗パターンが session.json の `patterns` で `count >= 2` の場合にのみ `[must]` プレフィックスを付与する。1 回のみの失敗は `[warning]` に留める。

例:
```
[info] Phase 2 で新規テスト追加パターンが定着
[warning] plugins/twl/scripts/ の変更で PATH 問題が発生しやすい
[must] マージ前に git diff origin/main --stat を実行して silent deletion がないか確認すること
```

**最終 Phase の場合**: 振り返りは実行するが PHASE_INSIGHTS は空文字列とする。

### Step 4: doobidoo 保存

```
mcp__doobidoo__memory_store({
  content: "## Phase ${P} Retrospective (Session: ${SESSION_ID})\n**Results**: done=${DONE}, fail=${FAIL}, skipped=${SKIP}\n**Patterns**: ${PATTERN_SUMMARY}\n**Insights**: ${INSIGHTS}",
  metadata: { type: "phase-retrospective", session_id: "${SESSION_ID}", phase: ${P} }
})
```

### Step 4.5: architecture 差分チェック

**スコープ**: done Issue の変更ファイルのみ（failed/skipped Issue は対象外）。**提示のみ** — session.json への記録・自動 Issue 化は行わない。

`architecture/` ディレクトリが存在しない場合、このステップ全体をスキップする（出力なし）。

1. Phase で変更されたファイルを収集する（Step 1 の **done Issue** から集約した変更ファイルリストを使用）
2. 変更ファイルのパスと `architecture/` 内のコンテキストファイルを照合し、乖離が疑われる候補を列挙する:

| 変更ファイルのパターン | 照合する architecture ファイル |
|---|---|
| `commands/`, `skills/`, `agents/` | `architecture/domain/model.md`（Component Mapping）|
| `scripts/state-*.sh` | `architecture/domain/model.md`（IssueState / SessionState）|
| `scripts/`, `commands/` (新規追加) | `architecture/domain/glossary.md`（MUST 用語）|
| `architecture/decisions/`, `architecture/contracts/` に影響する変更 | 対応 ADR / contract ファイル |

3. 乖離候補が 1 件以上あれば以下を提示する。自動 Issue 化は行わない:

```
以下の architecture 項目の更新を検討してください:
- <ファイルパス>: <照合する architecture ドキュメント> の更新が必要な可能性
```

候補がない場合は「architecture 更新候補なし」と出力して次へ進む。

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
