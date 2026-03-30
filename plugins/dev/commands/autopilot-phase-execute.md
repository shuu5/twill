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
| `$PROJECT_DIR` | プロジェクトディレクトリ |
| `$REPO_MODE` | `standard` or `worktree` |
| `$CROSS_ISSUE_WARNINGS` | cross-issue 警告の連想配列 |
| `$PHASE_INSIGHTS` | 前 Phase の知見（空の場合あり） |

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
ISSUES=$(sed -n "/  - phase: ${P}/,/  - phase:/p" "$PLAN_FILE" | grep -oP '    - \K\d+' || true)
```

### Step 2: 実行モード分岐

#### 2a. sequential モード（standard repo）

```
FOR each ISSUE in $ISSUES:
  # 再開時の done スキップ
  STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
  IF STATUS == "done":
    → 状態記録（done）、continue

  # should_skip 判定
  IF bash $SCRIPTS_ROOT/autopilot-should-skip.sh "$PLAN_FILE" "$ISSUE" "$SESSION_STATE_FILE" → exit 0:
    → 状態記録（skipped）、continue

  # Worker 起動（autopilot-launch を Read → 実行）
  → commands/autopilot-launch.md を Read → 実行

  # ポーリング（autopilot-poll を Read → 実行、POLL_MODE=single）
  POLL_MODE=single
  → commands/autopilot-poll.md を Read → 実行

  # 結果処理
  STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
  IF STATUS == "merge-ready":
    → commands/merge-gate.md を Read → 実行
  STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
  IF STATUS == "done":
    → tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true
    → 状態記録（done）
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
  STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
  IF STATUS == "done":
    → 状態記録（done）、continue
  IF bash $SCRIPTS_ROOT/autopilot-should-skip.sh → exit 0:
    → 状態記録（skipped）、continue
  ACTIVE_ISSUES+=($ISSUE)

# バッチ分割: ACTIVE_ISSUES を MAX_PARALLEL 個ずつに分割
TOTAL=${#ACTIVE_ISSUES[@]}
FOR ((BATCH_START=0; BATCH_START < TOTAL; BATCH_START += MAX_PARALLEL)):
  BATCH=(${ACTIVE_ISSUES[@]:$BATCH_START:$MAX_PARALLEL})

  # バッチ内の Issue を並列 launch
  FOR each ISSUE in $BATCH:
    STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
    IF STATUS == "done": continue
    → commands/autopilot-launch.md を Read → 実行

  # バッチ全体ポーリング
  POLL_MODE=phase
  ISSUES="${BATCH[*]}"
  → commands/autopilot-poll.md を Read → 実行

  # merge-ready の Issue に対して merge-gate を順次実行
  FOR each ISSUE in $BATCH:
    STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
    IF STATUS == "merge-ready":
      → commands/merge-gate.md を Read → 実行

  # window 管理 + 状態記録
  FOR each ISSUE in $BATCH:
    STATUS=$(bash $SCRIPTS_ROOT/state-read.sh --type issue --issue "$ISSUE" --field status)
    IF STATUS == "done":
      → tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true
      → 状態記録（done）
    ELIF STATUS == "failed":
      → 状態記録（fail）
```

### Step 3: 状態ファイル更新

各 Issue の完了状態を state-write.sh で記録:

```bash
# done の場合
bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot \
  --set "status=done" --set "pr_number=$PR_NUMBER"

# skipped の場合
bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot \
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
