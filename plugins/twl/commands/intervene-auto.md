---
type: atomic
tools: [Bash]
effort: low
---
# Layer 0 自動介入（intervene-auto）

Supervisor が自動実行する Layer 0 介入。non_terminal_chain_end 回復と Worker PR 未作成に対応する。

## 引数

- `--pattern <id>`: 介入パターン ID（`non-terminal-recovery` | `pr-create` | `permission-ui-response`）
- `--issue <num>`: 対象 Issue 番号
- `--branch <name>`: 対象 branch 名
- `--win <window>`: 対象 tmux window（`permission-ui-response` パターンで使用）

## フロー

### permission-ui-response パターン（Layer 0 Auto）

`[PERMISSION-PROMPT]` event 受信時に呼び出す。soft_deny ルールと照合し、結果に応じて Layer 0/1/2 に振り分ける。

```bash
WIN="${WIN_ARG}"  # --win で指定された tmux window

# Step P1: prompt_context 取得（tmux capture-pane -S -50）
prompt_context=$(tmux capture-pane -t "$WIN" -p -S -50 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

# Step P2: soft_deny_match.py で soft_deny ルールと照合
SOFT_DENY_RULES_PATH="${PLUGIN_ROOT}/skills/su-observer/refs/soft-deny-rules.md"
match_output=$(python3 -m twl.intervention.soft_deny_match \
  --prompt-context "$prompt_context" \
  --rules-path "$SOFT_DENY_RULES_PATH" \
  --session-id "${SESSION_ID:-}" \
  --observation-dir "$(git rev-parse --show-toplevel)/.observation" 2>&1)
match_exit=$?

# Step P3: 結果に応じて分岐
# no-match (exit 0) → Layer 0 Auto: inject "1" で承認
# match-confirm (exit 1) → STOP + Layer 1 Confirm 昇格
# match-escalate (exit 2) → STOP + Layer 2 Escalate 昇格
if [[ $match_exit -eq 0 ]]; then
  ACTION_TAKEN="auto-inject-1"
  # Layer 0 Auto: session-comm.sh inject $WIN "1" --force
  session-comm.sh inject "$WIN" "1" --force
  RESULT="approved"
elif [[ $match_exit -eq 1 ]]; then
  ACTION_TAKEN="STOP-confirm-escalation"
  # match-confirm → STOP + Layer 1 Confirm 昇格 (AskUserQuestion で文脈提示)
  RESULT="layer1-confirm"
  echo "[INTERVENTION] soft_deny match-confirm → Layer 1 Confirm 昇格: $match_output"
else
  ACTION_TAKEN="STOP-escalate-escalation"
  # match-escalate → STOP + Layer 2 Escalate 昇格 (Pilot escalation 通知)
  RESULT="layer2-escalate"
  echo "[INTERVENTION] soft_deny match-escalate → Layer 2 Escalate 昇格: $match_output"
fi

# 連続 soft_deny 検知: 同一セッション・同一カテゴリ 2 回以上検知で即時 STOP
# soft_deny 専用 state tracking (intervention-catalog パターン 13 とは独立)
if [[ $match_exit -ne 0 ]]; then
  soft_deny_count=$(python3 -m twl.intervention.soft_deny_match \
    --count-category "$(echo "$match_output" | grep matched_rule | cut -d: -f2 | tr -d ' ')" \
    --session-id "${SESSION_ID:-}" \
    --observation-dir "$(git rev-parse --show-toplevel)/.observation" 2>/dev/null || echo "0")
  if [[ "${soft_deny_count:-0}" -ge 2 ]]; then
    echo "[INTERVENTION] 連続 soft_deny 検知 (count=${soft_deny_count}) → 即時 STOP"
    RESULT="stop-consecutive-soft-deny"
  fi
fi

PATTERN_ID="permission-ui-response"
```

### Step 1: パターン検証

引数の `--pattern` を確認し、対応するパターンの前提条件を検証する。

**non-terminal-recovery の前提条件チェック**:

```bash
# PR 存在確認
gh pr list --head "$BRANCH" --json number,url --jq '.[0].url'
```

PR が存在しない場合はエラーを報告して終了。PR URL を記録する。

**pr-create の前提条件チェック**:

```bash
# 二重確認: PR が本当に存在しないか
gh pr list --head "$BRANCH" --json number,url --jq '.[0].url'
```

PR が既に存在する場合は「PR already exists」を報告して正常終了。

### Step 2: 修復実行

**non-terminal-recovery**:

```bash
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$(git rev-parse --show-toplevel)/.autopilot}"

# state を running に戻す
python3 -m twl.autopilot.state write \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "$ISSUE_NUM" --role worker \
  --set "status=running"

# force-done で merge-ready に遷移
python3 -m twl.autopilot.state write \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "$ISSUE_NUM" --role worker \
  --set "status=merge-ready" --force-done

# merge-gate 実行
python3 -m twl.autopilot.mergegate merge --force \
  --issue "$ISSUE_NUM" \
  --autopilot-dir "$AUTOPILOT_DIR"
```

**pr-create**:

```bash
# Issue タイトルを取得して PR 作成
ISSUE_TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title')
gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "$ISSUE_TITLE" \
  --body "Closes #${ISSUE_NUM}"
```

### Step 3: InterventionRecord 記録

```bash
OBSERVATION_DIR="$(git rev-parse --show-toplevel)/.observation/interventions"
mkdir -p "$OBSERVATION_DIR"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
cat > "$OBSERVATION_DIR/${TIMESTAMP}-${PATTERN_ID}.json" <<JSON
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pattern_id": "${PATTERN_ID}",
  "layer": "auto",
  "issue_num": ${ISSUE_NUM:-null},
  "branch": "${BRANCH}",
  "action_taken": "${ACTION_TAKEN}",
  "result": "${RESULT}",
  "notes": ""
}
JSON
```

## 出力

- 成功: `✓ Layer 0 Auto介入完了: <pattern-id> (issue #<num>)`
- 失敗: `✗ 介入失敗: <reason>`（ワークフローを停止しない）
