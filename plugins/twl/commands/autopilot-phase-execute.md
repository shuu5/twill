# Phase Issue ループ実行

1 Phase 分の全 Issue に対して launch → poll → merge-gate → window 管理を実行する。
state-read.sh / state-write.sh で状態管理。co-autopilot の Phase ループから呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$P` | 現在の Phase 番号 |
| `$SESSION_STATE_FILE` | session.json のパス |
| `$MODE` | `sequential` or `parallel` |
| `$PLAN_FILE` | plan.yaml のパス |
| `$SESSION_ID` | autopilot セッション ID |
| `$PROJECT_DIR` | プロジェクトディレクトリ（デフォルトリポジトリ） |
| `$REPO_MODE` | `standard` or `worktree` |
| `$CROSS_ISSUE_WARNINGS` | cross-issue 警告の連想配列 |
| `$PHASE_INSIGHTS` | 前 Phase の知見（空の場合あり） |
| `$REPOS_JSON` | repos セクション JSON（クロスリポジトリ時。空の場合は単一リポジトリ） |

## 実行ロジック（MUST）

### Step 0: MAX_PARALLEL の決定

```bash
MAX_PARALLEL=${DEV_AUTOPILOT_MAX_PARALLEL:-4}
if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  MAX_PARALLEL=4
fi
```

### Step 1: Phase 内 Issue リスト取得

```bash
# plan.yaml のフォーマット判定: クロスリポジトリ（{ number: N, repo: id }）or レガシー（bare int）
PHASE_BLOCK=$(sed -n "/  - phase: ${P}/,/  - phase:/p" "$PLAN_FILE")

if echo "$PHASE_BLOCK" | grep -q '{ number:'; then
  # クロスリポジトリ形式: { number: N, repo: repo_id } を解析
  # ISSUES_WITH_REPO: "repo_id:number" の配列
  ISSUES_WITH_REPO=()
  while IFS= read -r line; do
    num=$(echo "$line" | grep -oP 'number:\s*\K\d+')
    repo=$(echo "$line" | grep -oP 'repo:\s*\K[a-zA-Z0-9_-]+')
    [ -n "$num" ] && ISSUES_WITH_REPO+=("${repo}:${num}")
  done <<< "$(echo "$PHASE_BLOCK" | grep '{ number:')"
  # フォールバック: 混合フォーマット時の bare int もパース（_default repo として扱う）
  BARE_INTS=$(echo "$PHASE_BLOCK" | grep -P '^\s+- \d+$' | grep -oP '\d+' || true)
  for bi in $BARE_INTS; do
    ISSUES_WITH_REPO+=("_default:${bi}")
  done
  ISSUES=$(printf '%s\n' "${ISSUES_WITH_REPO[@]}" | cut -d: -f2)
else
  # レガシー形式: bare integer
  ISSUES=$(echo "$PHASE_BLOCK" | grep -oP '    - \K\d+' || true)
  ISSUES_WITH_REPO=()
  for issue in $ISSUES; do
    ISSUES_WITH_REPO+=("_default:${issue}")
  done
fi
```

Issue ごとのリポジトリ情報を autopilot-launch に渡す:

```bash
# ISSUES_WITH_REPO から repo コンテキストを展開
resolve_issue_repo_context() {
  local entry="$1"  # "repo_id:number"
  local repo_id="${entry%%:*}"
  ISSUE="${entry#*:}"
  ISSUE_REPO_ID="$repo_id"

  if [ "$repo_id" != "_default" ] && [ -n "$REPOS_JSON" ]; then
    ISSUE_REPO_OWNER=$(echo "$REPOS_JSON" | jq -r --arg k "$repo_id" '.[$k].owner')
    ISSUE_REPO_NAME=$(echo "$REPOS_JSON" | jq -r --arg k "$repo_id" '.[$k].name')
    ISSUE_REPO_PATH=$(echo "$REPOS_JSON" | jq -r --arg k "$repo_id" '.[$k].path')
    PILOT_AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"
  else
    ISSUE_REPO_OWNER=""
    ISSUE_REPO_NAME=""
    ISSUE_REPO_PATH=""
    PILOT_AUTOPILOT_DIR="${PROJECT_DIR}/.autopilot"
  fi
}
```

### Step 2: 実行モード分岐

#### 2a. sequential モード（standard repo）

```
FOR each ISSUE in $ISSUES:
  # 再開時の done スキップ
  STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
  IF STATUS == "done":
    → 状態記録（done）、continue

  # should_skip 判定
  IF AUTOPILOT_DIR=$AUTOPILOT_DIR bash "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-should-skip.sh" "$PLAN_FILE" "$ISSUE" "$SESSION_STATE_FILE" → exit 0:
    → 状態記録（skipped）、continue

  # Worker 起動（autopilot-launch を Read → 実行）
  → commands/autopilot-launch.md を Read → 実行

  # ポーリング（autopilot-poll を Read → 実行、POLL_MODE=single）
  POLL_MODE=single
  → commands/autopilot-poll.md を Read → 実行

  # proactive health check（論理的異常検知、crash-detect とは責務分離）
  STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
  IF STATUS == "running":
    HEALTH_OUTPUT=$(AUTOPILOT_DIR=$AUTOPILOT_DIR bash "${CLAUDE_PLUGIN_ROOT}/scripts/health-check.sh" --issue "$ISSUE" --window "ap-#${ISSUE}" 2>/dev/null) || {
      echo "WARNING: Issue #${ISSUE}: health check 異常検知: $HEALTH_OUTPUT"
    }

  # 結果処理
  STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
  IF STATUS == "merge-ready":
    → commands/merge-gate.md を Read → 実行
  STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
  IF STATUS == "done":
    → 状態記録（done）
    # tmux kill-window は autopilot-orchestrator.sh の cleanup_worker が担当（不変条件B）
  ELIF STATUS == "failed":
    → 状態記録（fail）
    → 残り全 Issue を skipped に設定
    → break
```

#### 2b. parallel モード（worktree repo）

```
# 有効 Issue リストを構築（skip/done を除外）
ACTIVE_ISSUES=()
FOR each ISSUE in $ISSUES:
  STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
  IF STATUS == "done":
    → 状態記録（done）、continue
  IF AUTOPILOT_DIR=$AUTOPILOT_DIR bash "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-should-skip.sh" → exit 0:
    → 状態記録（skipped）、continue
  ACTIVE_ISSUES+=($ISSUE)

# バッチ分割: ACTIVE_ISSUES を MAX_PARALLEL 個ずつに分割
TOTAL=${#ACTIVE_ISSUES[@]}
FOR ((BATCH_START=0; BATCH_START < TOTAL; BATCH_START += MAX_PARALLEL)):
  BATCH=(${ACTIVE_ISSUES[@]:$BATCH_START:$MAX_PARALLEL})

  # バッチ内の Issue を並列 launch
  FOR each ISSUE in $BATCH:
    STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
    IF STATUS == "done": continue
    → commands/autopilot-launch.md を Read → 実行

  # バッチ全体ポーリング
  POLL_MODE=phase
  ISSUES="${BATCH[*]}"
  → commands/autopilot-poll.md を Read → 実行

  # proactive health check（論理的異常検知、crash-detect とは責務分離）
  FOR each ISSUE in $BATCH:
    STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
    IF STATUS == "running":
      HEALTH_OUTPUT=$(AUTOPILOT_DIR=$AUTOPILOT_DIR bash "${CLAUDE_PLUGIN_ROOT}/scripts/health-check.sh" --issue "$ISSUE" --window "ap-#${ISSUE}" 2>/dev/null) || {
        echo "WARNING: Issue #${ISSUE}: health check 異常検知: $HEALTH_OUTPUT"
      }

  # merge-ready の Issue に対して merge-gate を順次実行
  FOR each ISSUE in $BATCH:
    STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
    IF STATUS == "merge-ready":
      → commands/merge-gate.md を Read → 実行

  # window 管理 + 状態記録
  FOR each ISSUE in $BATCH:
    STATUS=$(AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state read --type issue --issue "$ISSUE" --field status)
    IF STATUS == "done":
      → 状態記録（done）
      # tmux kill-window は autopilot-orchestrator.sh の cleanup_worker が担当（不変条件B）
    ELIF STATUS == "failed":
      → 状態記録（fail）
```

### Step 3: 状態ファイル更新

各 Issue の完了状態を state-write.sh で記録:

```bash
# done の場合
AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
  --set "status=done" --set "pr_number=$PR_NUMBER"

# skipped の場合
AUTOPILOT_DIR=$AUTOPILOT_DIR python3 -m twl.autopilot.state write --type issue --issue "$ISSUE" --role pilot \
  --set "status=failed" --set "failure={\"message\": \"dependency_failed\", \"step\": \"skip\"}"

# fail 情報は crash-detect.sh / autopilot-poll が既に記録済み
```

## 不変条件の遵守（MUST）

- **不変条件 D**: 依存先 fail 時は後続 Issue を自動 skip
- **不変条件 E**: merge-gate リジェクト → 再実行は 1 Issue 最大 1 回。2 回目は確定失敗
- **不変条件 F**: merge-gate 失敗時に rebase を試みてはならない

## 禁止事項（MUST NOT）

- マーカーファイルを参照してはならない
- `.fail` window を自動クローズしてはならない
- merge-gate 失敗時に rebase を試みてはならない（停止のみ）
- merge-gate リジェクト後の再実行を 2 回以上行ってはならない
