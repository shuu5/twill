# Monitor Channel Catalog

su-observer が Wave 管理時に使用する Monitor tool チャネルの標準定義。
Wave 開始時に本カタログから Wave 種別に応じたチャネルを選択して Monitor tool を起動する。

## チャネル一覧

| Channel | 検知対象 | 閾値 | 介入層 |
|---|---|---|---|
| INPUT-WAIT | 全 window の approval/input UI 長期滞在 | 即時 | Auto |
| PILOT-IDLE | Pilot の Skedaddling/Frolicking/Background poll 継続 | 5分 | Confirm |
| STAGNATE | state file 群の mtime 未更新 | 10分 | Confirm |
| WORKERS | worker window 出現・消失 | 即時 | Auto |
| PHASE-DONE | PHASE_COMPLETE 検知 | 即時 | Auto |
| NON-TERMINAL | `>>> 実装完了:` 後の chain 不遷移 | 2分 | Confirm |
| BUDGET-LOW | 5h rolling budget 残量 | 残り 15 分（設定可） | Auto |

---

## [INPUT-WAIT] — approval UI / input-waiting 検知

**検知対象**: `session-state.sh state <window>` が `input-waiting` を返すウィンドウの長期滞在

**閾値**: 即時（状態検出後すぐに報告）

**bash スニペット（Monitor tool 向け）:**

```bash
# INPUT-WAIT: 全ウィンドウの input-waiting を検知
# Monitor tool の pattern として使用
pattern='input-waiting'
description='[INPUT-WAIT] approval UI または input prompt が検出されました'
```

**cld-observe-loop での使用例:**
```bash
# ウィンドウ名パターンを指定して input-waiting を監視
SESSION_STATE="$(dirname "$0")/../plugins/session/scripts/session-state.sh"
for win in $(tmux list-windows -a -F '#{session_name}:#{window_name}' 2>/dev/null); do
  state=$(bash "$SESSION_STATE" state "$win" 2>/dev/null || echo "unknown")
  if [[ "$state" == "input-waiting" ]]; then
    echo "[INPUT-WAIT] window=$win は input-waiting です。介入が必要な可能性があります。"
  fi
done
```

**Wave 6 参考実装**（approval UI 検知に実績あり）:
```bash
# Pilot window の input-waiting を Monitor tool でストリーミング検知
# session-state.sh が "Enter to select" / "承認しますか" / "[y/N]" を input-waiting と返す
```

**hook ベース検知（プライマリ — #570）:**

`.supervisor/events/input-wait-*` が存在する場合、即時 `[INPUT-WAIT]` として報告する:

```bash
# INPUT-WAIT: input-wait ファイル存在プライマリ検知
EVENTS_DIR=".supervisor/events"
IW_FOUND=false

for iw_file in "${EVENTS_DIR}"/input-wait-* 2>/dev/null; do
  if [[ -f "$iw_file" ]]; then
    IW_FOUND=true
    IW_SESSION=$(jq -r '.session_id // empty' "$iw_file" 2>/dev/null || echo "")
    echo "[INPUT-WAIT] input-wait イベント検出: session=${IW_SESSION}（hook プライマリ）"
  fi
done

# input-wait ファイル不在 → 既存 session-state.sh polling にフォールバック
if [[ "$IW_FOUND" == "false" ]]; then
  # 既存の session-state.sh state <window> polling を実行する
  :
fi
```

---

## [PILOT-IDLE] — Pilot 停滞検知

**検知対象**: Pilot window が Skedaddling/Frolicking/Background poll 等のアイドル処理で 5 分以上停滞

**閾値**: 5分（300秒）

**bash スニペット:**

```bash
# PILOT-IDLE: Pilot window の processing 継続時間を監視
PILOT_IDLE_THRESHOLD=300  # 5分

check_pilot_idle() {
  local pilot_win="${1:-}"
  local state_file="${2:-.supervisor/pilot-last-active}"
  
  local current_state
  current_state=$(bash plugins/session/scripts/session-state.sh state "$pilot_win" 2>/dev/null || echo "unknown")
  
  if [[ "$current_state" == "processing" ]]; then
    local last_active
    last_active=$(cat "$state_file" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local elapsed=$(( now - last_active ))
    
    if [[ $elapsed -gt $PILOT_IDLE_THRESHOLD ]]; then
      echo "[PILOT-IDLE] Pilot が ${elapsed}秒 processing 状態です。確認が必要です。"
      return 1
    fi
  else
    date +%s > "$state_file"
  fi
  return 0
}
```

---

## [STAGNATE] — state file mtime 監視

**検知対象**: 以下の state file 群の mtime が 10 分（600秒）以上更新されない場合

**監視対象 path（明示）:**
- `.supervisor/working-memory.md` — su-observer working memory
- `.autopilot/waves/<N>.summary.md` — Wave 進捗サマリ（N は現在の Wave 番号）
- `.autopilot/checkpoints/*.json` — e2e-screening / ac-verify / phase-review チェックポイント

**閾値**: 10分（600秒）

**bash スニペット:**

```bash
# STAGNATE: state file 群の mtime を監視
STAGNATE_THRESHOLD=600  # 10分

check_stagnate() {
  local autopilot_dir="${1:-.autopilot}"
  local wave_num="${2:-}"
  local now
  now=$(date +%s)
  
  local stagnate_files=(
    ".supervisor/working-memory.md"
    "${autopilot_dir}/checkpoints"
  )
  [[ -n "$wave_num" ]] && stagnate_files+=("${autopilot_dir}/waves/${wave_num}.summary.md")
  
  for path in "${stagnate_files[@]}"; do
    if [[ -e "$path" ]]; then
      local mtime
      mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
      local age=$(( now - mtime ))
      if [[ $age -gt $STAGNATE_THRESHOLD ]]; then
        echo "[STAGNATE] $path が ${age}秒間更新されていません（閾値: ${STAGNATE_THRESHOLD}s）"
      fi
    fi
  done
}
```

**hook ベース検知（プライマリ — #570）:**

`.supervisor/events/heartbeat-*` が存在する場合、mtime を確認する。heartbeat ファイルが不在の場合のみ既存 polling にフォールバックする:

```bash
# STAGNATE: heartbeat mtime プライマリ検知
STAGNATE_THRESHOLD="${AUTOPILOT_STAGNATE_SEC:-600}"
NOW=$(date +%s)
EVENTS_DIR=".supervisor/events"
HB_FOUND=false

for hb_file in "${EVENTS_DIR}"/heartbeat-* 2>/dev/null; do
  [[ -f "$hb_file" ]] || continue
  HB_FOUND=true
  HB_MTIME=$(stat -c %Y "$hb_file" 2>/dev/null || echo "0")
  HB_AGE=$(( NOW - HB_MTIME ))
  if [[ $HB_AGE -gt $STAGNATE_THRESHOLD ]]; then
    echo "[STAGNATE] heartbeat ${hb_file##*/} が ${HB_AGE}秒間更新されていません（hook プライマリ）"
  fi
done

# heartbeat ファイル不在 → 既存 polling にフォールバック
if [[ "$HB_FOUND" == "false" ]]; then
  check_stagnate ".autopilot"  # 既存の check_stagnate 関数を呼び出す
fi
```

---

## [WORKERS] — worker window 出現・消失検知

**検知対象**: `ap-*` パターンの worker window の出現・消失

**閾値**: 即時

**bash スニペット:**

```bash
# WORKERS: worker window の変化を検知
check_workers() {
  local pattern="${1:-ap-*}"
  local snapshot_file="${2:-.supervisor/worker-snapshot.txt}"
  
  # glob パターンを安全な正規表現に変換（ReDoS 対策: 特殊文字をエスケープ後に * → .* 変換）
  # ReDoS 対策（Issue #525）: $1 を未検証のまま grep -E に渡さないようエスケープする
  local safe_pattern
  safe_pattern=$(printf '%s' "${pattern//\*/GLOB_STAR}" | sed 's/[.+?()[\]{}^$|\\]/\\&/g; s/GLOB_STAR/.*/g')
  local current_workers
  current_workers=$(tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -E "^${safe_pattern}$" | sort || true)
  
  if [[ -f "$snapshot_file" ]]; then
    local prev_workers
    prev_workers=$(cat "$snapshot_file")
    
    # prev_workers が空の場合は新規 worker のみ報告（空行が comm に渡ることを防止）
    if [[ -z "$prev_workers" ]]; then
      [[ -n "$current_workers" ]] && echo "[WORKERS] 新規 worker: $current_workers"
    else
      local new_workers
      new_workers=$(comm -13 <(printf '%s\n' "$prev_workers") <(printf '%s\n' "$current_workers"))
      local gone_workers
      gone_workers=$(comm -23 <(printf '%s\n' "$prev_workers") <(printf '%s\n' "$current_workers"))
      
      [[ -n "$new_workers" ]] && echo "[WORKERS] 新規 worker: $new_workers"
      [[ -n "$gone_workers" ]] && echo "[WORKERS] 消失 worker: $gone_workers"
    fi
  fi
  
  echo "$current_workers" > "$snapshot_file"
}
```

**hook ベース補完（session-end — #570）:**

`.supervisor/events/session-end-*` が存在する場合、Worker 消失の補完情報として追記する（読み出し後に個別削除）:

```bash
# WORKERS: session-end 補完検知（常時 polling と併用）
EVENTS_DIR=".supervisor/events"

for se_file in "${EVENTS_DIR}"/session-end-* 2>/dev/null; do
  if [[ -f "$se_file" ]]; then
    SE_SESSION=$(jq -r '.session_id // empty' "$se_file" 2>/dev/null || echo "")
    echo "[WORKERS] session-end 検出: session=${SE_SESSION}（補完）"
    rm -f "$se_file" 2>/dev/null || true  # 読み出し後に個別削除（SHALL）
  fi
done
```

**注意**: WORKERS チャンネルは `tmux list-windows` / `session-state.sh list --json` が常時プライマリ。session-end は消失確認の補完情報として使用する。

---

## [PHASE-DONE] — Phase 完了検知

**検知対象**: `PHASE_COMPLETE` シグナルまたは `.autopilot/waves/<N>.summary.md` の `status: done` 更新

**閾値**: 即時

**bash スニペット:**

```bash
# PHASE-DONE: Wave/Phase 完了を検知
check_phase_done() {
  local autopilot_dir="${1:-.autopilot}"
  local wave_num="${2:-}"
  
  [[ -z "$wave_num" ]] && return 0
  
  local summary="${autopilot_dir}/waves/${wave_num}.summary.md"
  if [[ -f "$summary" ]] && grep -q "status: done" "$summary" 2>/dev/null; then
    echo "[PHASE-DONE] Wave ${wave_num} が完了しました。"
    return 1
  fi
  return 0
}
```

---

## [NON-TERMINAL] — 実装完了後の chain 不遷移検知

**検知対象**: `>>> 実装完了:` シグナルが出力されてから 2 分以上 chain が次ステップに遷移しない

**閾値**: 2分（120秒）

**bash スニペット:**

```bash
# NON-TERMINAL: 実装完了後の chain 遷移待ち
NON_TERMINAL_THRESHOLD=120  # 2分

check_non_terminal() {
  local pilot_win="${1:-}"
  local signal_file="${2:-.supervisor/impl-complete-at}"
  
  if tmux capture-pane -p -t "$pilot_win" 2>/dev/null | grep -q ">>> 実装完了:"; then
    if [[ ! -f "$signal_file" ]]; then
      date +%s > "$signal_file"
    fi
    local signal_at
    signal_at=$(cat "$signal_file")
    local now
    now=$(date +%s)
    local elapsed=$(( now - signal_at ))
    if [[ $elapsed -gt $NON_TERMINAL_THRESHOLD ]]; then
      echo "[NON-TERMINAL] 実装完了シグナルから ${elapsed}秒経過しましたが chain が遷移していません。"
      return 1
    fi
  else
    rm -f "$signal_file"
  fi
  return 0
}
```

**hook ベース検知（プライマリ — #570）:**

`.supervisor/events/skill-step-*` が存在する場合、JSON の `skill` フィールドから skill 完了パターンを確認する。skill-step ファイルが不在の場合のみ既存 polling にフォールバックする:

```bash
# NON-TERMINAL: skill-step 内容解析プライマリ検知
NON_TERMINAL_THRESHOLD=120  # 2分
NOW=$(date +%s)
EVENTS_DIR=".supervisor/events"
SS_FOUND=false

for ss_file in "${EVENTS_DIR}"/skill-step-* 2>/dev/null; do
  [[ -f "$ss_file" ]] || continue
  SS_FOUND=true
  SKILL_NAME=$(jq -r '.skill // empty' "$ss_file" 2>/dev/null || echo "")
  SS_TIMESTAMP=$(jq -r '.timestamp // 0' "$ss_file" 2>/dev/null || echo "0")
  if [[ -n "$SKILL_NAME" ]]; then
    SS_AGE=$(( NOW - SS_TIMESTAMP ))
    if [[ $SS_AGE -gt $NON_TERMINAL_THRESHOLD ]]; then
      echo "[NON-TERMINAL] skill=${SKILL_NAME} が ${SS_AGE}秒前に実行されましたが chain が遷移していません（hook プライマリ）"
    fi
  fi
done

# skill-step ファイル不在 → 既存 session-comm.sh capture + grep にフォールバック
if [[ "$SS_FOUND" == "false" ]]; then
  check_non_terminal "$pilot_win"  # 既存の check_non_terminal 関数を呼び出す
fi
```

---

## [BUDGET-LOW] — 5h rolling budget 残量検知

**検知対象**: Claude Code の tmux status line から `budget: <残量>` をパースし、閾値以下になった場合に停止シーケンスを自動実行する

**閾値**: 残り 15 分（`.supervisor/budget-config.json` の `threshold_minutes` フィールドで override 可能。デフォルト 15）

**検知方法**: `tmux capture-pane -t "$PILOT_WINDOW" -p -S -1` で status line をキャプチャし正規表現でパース。取得不能の場合は `session-comm.sh capture` にフォールバック。それでも取得不能な場合は検知をスキップし stderr に警告。

**介入層**: Layer 0 Auto（SU-1 に従う）

**bash スニペット:**

```bash
# BUDGET-LOW: status line から budget 残量をパース
BUDGET_THRESHOLD_MIN=15  # デフォルト閾値（分）

get_budget_minutes() {
  local pilot_win="${1:-}"
  local raw
  # status line から取得
  raw=$(tmux capture-pane -t "$pilot_win" -p -S -1 2>/dev/null \
    | grep -oP '(?:budget|Budget):\s*\K[0-9]+[hm]' | tail -1 || echo "")
  # フォールバック: full pane から取得
  if [[ -z "$raw" ]]; then
    raw=$(plugins/session/scripts/session-comm.sh capture "$pilot_win" 2>/dev/null \
      | grep -oP '(?:budget|Budget):\s*\K[0-9]+[hm]' | tail -1 || echo "")
  fi
  if [[ -z "$raw" ]]; then
    echo "[BUDGET-LOW] WARN: budget 情報を取得できません。" >&2
    echo "-1"
    return 0
  fi
  if [[ "$raw" =~ ^([0-9]+)h$ ]]; then
    echo $(( ${BASH_REMATCH[1]} * 60 ))
  elif [[ "$raw" =~ ^([0-9]+)m$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "-1"
  fi
}

check_budget_low() {
  local pilot_win="${1:-}"
  local threshold="${BUDGET_THRESHOLD_MIN}"
  local budget_min
  budget_min=$(get_budget_minutes "$pilot_win")
  if [[ "$budget_min" -ge 0 && "$budget_min" -le "$threshold" ]]; then
    echo "[BUDGET-LOW] 5h budget 残り ${budget_min}分（閾値: ${threshold}分）。安全停止シーケンスを開始します。"
    return 1
  fi
  return 0
}
```

**停止シーケンス（BUDGET-LOW 検知時）:**

1. orchestrator 停止: `.autopilot/orchestrator.pid` または `ps aux | grep autopilot-orchestrator` で PID 取得 → `kill <PID>`（Worker inject ループを止める）
2. 全 `ap-*` window に `tmux send-keys -t "<window>" Escape` を送信（kill 禁止 — 不変条件）
3. `.supervisor/budget-pause.json` に停止状態を記録:
   ```json
   {
     "status": "paused",
     "paused_at": "<ISO 8601>",
     "estimated_recovery": "<停止時刻 + 90分>",
     "cron_id": "<CronCreate で設定したID>",
     "paused_workers": ["ap-569", "ap-570"],
     "orchestrator_pid": 12345
   }
   ```
4. CronCreate で回復時刻（保守的推定: 停止時刻 + 90 分）に su-observer の再起動をスケジュール

**再開シーケンス（Step 0 の budget-pause.json 復帰パスで実行）:**

1. 各 `paused_workers` の `session-state.sh state <window>` → `idle` or `input-waiting` 確認
2. Pilot window 状態確認
3. orchestrator の再起動（`session-comm.sh inject` で orchestrator 起動コマンド送信）
4. 各 Worker に `session-comm.sh inject` で再開指示送信
5. 全 Worker が `processing` 状態に遷移したことを確認
6. `budget-pause.json` の `status` を `resumed` に更新

---

---

## `cld-observe-any` 標準スニペット（推奨実装）

既存の Monitor tool + cld-observe-loop と**補完関係**にある。置換ではなく併用する。

### 基本起動（Worker 群監視）

```bash
# Monitor tool と cld-observe-any を必ず同時起動（SKILL.md L172 ポリシー踏襲）
plugins/session/scripts/cld-observe-any \
  --pattern 'ap-.*' \
  --interval 180 \
  --stagnate-sec 600 \
  --budget-threshold 15 \
  --event-dir .supervisor/events \
  --notify-dir /tmp/claude-notifications
```

### Pilot/co-issue 等の対話型セッション監視

```bash
# 特定 window を多指標 AND 条件で監視
plugins/session/scripts/cld-observe-any \
  --window "$PILOT_WINDOW" \
  --interval 30 \
  --complete-regex "PHASE_COMPLETE" \
  --complete-require-cmd-echo "gh issue edit [0-9]+ --add-label refined" \
  --stagnate-sec 300
```

### 単発チェック（--once）

```bash
# 現在状態を一回評価して exit（inline 判定に使用）
result=$(plugins/session/scripts/cld-observe-any \
  --window "$WIN" --once 2>/dev/null)
echo "event: $result"
```

### イベント種別と対応アクション

| イベント | 説明 | 対応 |
|---|---|---|
| `[PANE-DEAD]` | pane 終了 | Worker 消失確認 → 後処理 |
| `[ERROR-STATE]` | Traceback/command not found | ログ確認 → 自動修復または Escalate |
| `[BUDGET-LOW]` | budget 残量 ≤ 閾値 | 停止シーケンス（BUDGET-LOW 定義参照） |
| `[PHASE-COMPLETE]` | フェーズ完了フレーズ検知 | 次 Wave 移行 |
| `[REVIEW-READY]` | Submit answers 表示 | inject で submit |
| `[MENU-READY]` | Enter to select 表示 | inject + Tab + Enter |
| `[FREEFORM-READY]` | [y/N]/Press up 表示 | inject で応答 |
| `[STAGNATE-N]` | log age ≥ N 秒 | STAGNATE 介入フロー |

---

## Wave 種別ごとのチャネル選択ガイド

| Wave 種別 | 推奨チャネル |
|---|---|
| co-autopilot 実行中（全般） | INPUT-WAIT + STAGNATE + WORKERS + BUDGET-LOW |
| Phase 実行中（Worker 並列） | INPUT-WAIT + WORKERS + PHASE-DONE |
| 長時間 Pilot 処理 | PILOT-IDLE + NON-TERMINAL + BUDGET-LOW |
| デバッグ・問題調査 | INPUT-WAIT + STAGNATE（最小セット） |
