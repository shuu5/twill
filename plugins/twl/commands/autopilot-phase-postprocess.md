# Phase 後処理

1 Phase 分の後処理（collect → retrospective → patterns → cross-issue）を統合実行する。
co-autopilot の Phase ループから呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$P` | 現在の Phase 番号 |
| `$SESSION_STATE_FILE` | session.json のパス |
| `$PLAN_FILE` | plan.yaml のパス |
| `$SESSION_ID` | autopilot セッション ID |
| `$PHASE_COUNT` | 総 Phase 数 |

## 出力変数

| 変数 | 説明 |
|------|------|
| `$PHASE_INSIGHTS` | 次 Phase 向け知見（最終 Phase では空） |
| `$CROSS_ISSUE_WARNINGS` | cross-issue 警告の連想配列（最終 Phase では空） |

## 実行ロジック（MUST）

### Step 0: 開始時刻記録

```bash
POSTPROCESS_START_TIME=$(date +%s)
```

### Step 1: Phase 内 Issue リスト取得

```bash
ISSUES=$(sed -n "/  - phase: ${P}/,/  - phase:/p" "$PLAN_FILE" | grep -oP '    - \K\d+' || true)
```

### Step 2: autopilot-collect を Read → 実行

`commands/autopilot-collect.md` を Read し、実行する。
Phase 内の done Issue から PR 差分を収集し session.json に保存。

### Step 3: autopilot-retrospective を Read → 実行

`commands/autopilot-retrospective.md` を Read し、実行する。
Phase の成功/失敗パターンを分析し、次 Phase 向け知見を生成。PHASE_INSIGHTS を設定。

### Step 4: autopilot-patterns を Read → 実行

`commands/autopilot-patterns.md` を Read し、実行する。
state-read で取得した failure 情報から繰り返しパターンを検出。

### Step 5: cross-issue（条件付き）

```
IF P < PHASE_COUNT（最終 Phase でない）:
  NEXT_P=$((P + 1))
  NEXT_PHASE_ISSUES=$(sed -n "/  - phase: ${NEXT_P}/,/  - phase:/p" "$PLAN_FILE" | grep -oP '    - \K\d+' || true)
  → commands/autopilot-cross-issue.md を Read → 実行
  → CROSS_ISSUE_WARNINGS を設定
ELSE:
  PHASE_INSIGHTS=""
  declare -A CROSS_ISSUE_WARNINGS=()
```

### Step 6: postprocess_duration_sec 記録

```bash
POSTPROCESS_END_TIME=$(date +%s)
POSTPROCESS_DURATION_SEC=$((POSTPROCESS_END_TIME - POSTPROCESS_START_TIME))
```

session.json の `.retrospectives` 配列から当該 Phase のエントリを検索し、`postprocess_duration_sec` を追記する（エントリが存在しない場合はスキップ）:

```bash
bash "$(dirname "$SESSION_STATE_FILE")/../plugins/twl/scripts/session-atomic-write.sh" \
  "$SESSION_STATE_FILE" \
  --argjson phase "$P" --argjson dur "$POSTPROCESS_DURATION_SEC" \
  '.retrospectives = [.retrospectives[] | if .phase == $phase then . + {postprocess_duration_sec: $dur} else . end]'
```

## 禁止事項（MUST NOT）

- 最終 Phase で cross-issue を実行してはならない
- 後処理の実行順序を変更してはならない（collect → retrospective → patterns → cross-issue）
- マーカーファイルを参照してはならない
