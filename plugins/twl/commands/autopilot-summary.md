---
tools: [mcp__doobidoo__memory_store, Bash, Skill, Read]
type: atomic
effort: medium
maxTurns: 30
---

# 完了サマリーと通知

全 Phase 完了後にセッション完了レポートを出力する。
co-autopilot Step 5 から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$PLAN_FILE` | plan.yaml のパス |
| `$SESSION_ID` | autopilot セッション ID |
| `$SESSION_STATE_FILE` | session.json のパス |
| `$PHASE_COUNT` | 総 Phase 数 |

## 実行ロジック（MUST）

### Step 1: ALL_ISSUES の構築（MUST）

plan.yaml の全 Phase から Issue リストを構築する。未定義変数を使用してはならない。

```bash
ALL_ISSUES=""
for P in $(seq 1 $PHASE_COUNT); do
  PHASE_ISSUES=$(sed -n "/  - phase: ${P}/,/  - phase:/p" "$PLAN_FILE" | grep -oP '    - \K\d+' || true)
  ALL_ISSUES="${ALL_ISSUES} ${PHASE_ISSUES}"
done
ALL_ISSUES=$(echo "$ALL_ISSUES" | xargs)
```

### Step 2: サマリー集計

```bash
DONE_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
DONE_ISSUES=""; FAIL_ISSUES=""; SKIP_ISSUES=""

for ISSUE in $ALL_ISSUES; do
  STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
  case "$STATUS" in
    done)
      DONE_COUNT=$((DONE_COUNT + 1))
      PR=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field pr_number)
      DONE_ISSUES="${DONE_ISSUES}\n  #${ISSUE} → PR #${PR}"
      ;;
    failed)
      FAIL_COUNT=$((FAIL_COUNT + 1))
      FAILURE=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field failure)
      REASON=$(echo "$FAILURE" | jq -r '.message // "unknown"')
      FAIL_ISSUES="${FAIL_ISSUES}\n  #${ISSUE} (${REASON})"
      ;;
    *)
      SKIP_COUNT=$((SKIP_COUNT + 1))
      SKIP_ISSUES="${SKIP_ISSUES}\n  #${ISSUE}"
      ;;
  esac
done
```

### Step 2.5: セッション監査（session-audit）

session.json の started_at から経過時間を算出し、session-audit を自動実行:

```bash
STARTED_AT=$(python3 -m twl.autopilot.state read --type session --field started_at)
if [ -n "$STARTED_AT" ]; then
  STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "")
  if [ -n "$STARTED_EPOCH" ]; then
    NOW_EPOCH=$(date +%s)
    ELAPSED_HOURS=$(( (NOW_EPOCH - STARTED_EPOCH) / 3600 + 1 ))
    if [ "$ELAPSED_HOURS" -le 0 ] 2>/dev/null; then
      SINCE_PARAM="24h"
    else
      SINCE_PARAM="${ELAPSED_HOURS}h"
    fi
  else
    SINCE_PARAM="24h"
  fi
else
  SINCE_PARAM="24h"
fi
```

`/twl:session-audit --since $SINCE_PARAM` を Skill tool で実行する。

失敗時: 「session-audit: 実行失敗（スキップ）」を設定。ワークフロー停止しない。

### Step 3: レポート出力

```
==========================================
  Autopilot パイロットセッション完了
==========================================
  Session: <session_id>

  成功: N件
    #19 → PR #42
  失敗: N件
    #20 (merge_failed)
  スキップ: N件
    #23

## 検出パターン
  - [tech-debt] ...: N件
  - [failure] ...: N件

## Phase Retrospective サマリー
  Phase 1: ...
  Phase 2: ...

## self-improve 改善機会
  - #XX [Self-Improve] ...

## セッション監査結果
  ...
==========================================
```

### Step 4: doobidoo 保存

```
mcp__doobidoo__memory_store({
  content: "## Session Completion Report (Session: ${SESSION_ID})\n**Results**: done=${DONE_COUNT}, fail=${FAIL_COUNT}, skip=${SKIP_COUNT}",
  metadata: { type: "session-completion-report", session_id: "${SESSION_ID}" }
})
```

### Step 5: セッションアーカイブ

```bash
python3 -m twl.autopilot.session archive
```

### Step 6: 通知

```bash
if command -v notify-send &>/dev/null; then
  if [ $FAIL_COUNT -eq 0 ]; then
    notify-send -u critical "Autopilot: 全Issue完了" "Session $SESSION_ID: 全Issue正常完了"
  else
    notify-send -u critical "Autopilot: 一部失敗あり" "Session $SESSION_ID: 失敗Issueがあります"
  fi
fi

if command -v pw-play &>/dev/null; then
  SOUND="/usr/share/sounds/freedesktop/stereo/complete.oga"
  [ -f "$SOUND" ] && pw-play --volume=0.5 "$SOUND" 2>/dev/null || true
fi
```

## 禁止事項（MUST NOT）

- マーカーファイルを参照してはならない（state-read で全 Issue 状態を取得）
- ALL_ISSUES を未定義変数から構築してはならない（plan.yaml から正しく構築）
- session-audit 失敗でワークフロー全体を停止してはならない
