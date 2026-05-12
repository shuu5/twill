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
| BUDGET-LOW | 5h rolling budget 残量 | token残量 40分以下 or cycle reset まで 5分以下（設定可） | Auto |
| BUDGET-ALERT | Monitor watcher が検知した budget threshold 超過 | threshold_percent (default 90%) | Auto |
| PERMISSION-PROMPT | Worker window の permission prompt 出現（`1. Yes, proceed` 等） | 即時（thinking 中でも emit） | Auto（deny rule 該当時 Confirm/Escalate 昇格） |
| **PILOT-PHASE-COMPLETE** | Pilot 内部 chain の Phase/Issue 完了 signal | 即時 | Auto |
| **PILOT-ISSUE-MERGED** | Pilot が merge-gate で Issue merge を完了した signal | 即時 | Auto |
| **PILOT-WAVE-COLLECTED** | Pilot が wave-collect を完了した signal | 即時 | Auto |
| [IDLE-COMPLETED] | completion phrase 確認済み controller の idle 確定 (cleanup-trigger) | 60s debounce | Confirm（IDLE_COMPLETED_AUTO_KILL=1 時は Auto） |

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
SESSION_STATE="$(git rev-parse --show-toplevel)/plugins/session/scripts/session-state.sh"  # cross-plugin reference
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
  current_state=$(bash "$(git rev-parse --show-toplevel)/plugins/session/scripts/session-state.sh" state "$pilot_win" 2>/dev/null || echo "unknown")  # cross-plugin reference
  
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

**検知対象**: Claude Code の tmux status line から実フォーマット `5h:XX%(YYm)`（例: `5h:10%(4h21m)`）をパースし、2 軸独立判定で閾値以下になった場合に停止シーケンスを自動実行する

**フォーマット `5h:XX%(YYm)` の意味（重要）**:
- `5h` — 5 時間単位の rolling budget cycle
- `XX%` — **消費 token 比率**（使用した量、0〜100%）
- `(YYm)` — **次の cycle reset までの wall-clock remaining**（cycle 残り時間）
- ⚠️ `(YYm)` は token 残量ではない。`XX%` と独立した別軸（#1022）

**2 軸独立判定（OR 発火）**:
- **軸1 (consumption-based)**: token 残量 = `300 × (100 - XX%) / 100` ≤ `threshold_remaining_minutes`（default 40分）
- **軸2 (cycle-based)**: cycle reset wall-clock `(YYm)` ≤ `threshold_cycle_minutes`（default 5分）
- 設定: `.supervisor/budget-config.json` で `threshold_remaining_minutes` / `threshold_cycle_minutes` を override 可能

**閾値デフォルト**:
- `threshold_remaining_minutes` = 40（token 残量 40分以下で発火）
- `threshold_cycle_minutes` = 5（cycle reset まで 5分以下で発火）

**検知方法**: `tmux capture-pane -t "$PILOT_WINDOW" -p -S -1` で status line をキャプチャし正規表現でパース。取得不能の場合は `session-comm.sh capture` にフォールバック。それでも取得不能な場合は検知をスキップし stderr に警告。

**介入層**: Layer 0 Auto（SU-1 に従う）

**bash スニペット:**

```bash
# BUDGET-LOW: status line から 2 軸 budget 判定（実フォーマット: 5h:XX%(YYm)）
# 軸1 (consumption-based): token残量 = 300 × (100 - pct%) / 100 ≤ threshold_remaining_minutes
# 軸2 (cycle-based): (YYm) = cycle reset wall-clock ≤ threshold_cycle_minutes
# ※ (YYm) は cycle reset wall-clock であり token 残量ではない（#1022）
BUDGET_THRESHOLD_REMAINING=40  # 軸1 デフォルト閾値（token 残量 分）
BUDGET_THRESHOLD_CYCLE=5       # 軸2 デフォルト閾値（cycle reset wall-clock 分）

get_budget_info() {
  local pilot_win="${1:-}"
  local pct raw
  # status line から取得（実フォーマット: 5h:XX%(YYm)）
  pct=$(tmux capture-pane -t "$pilot_win" -p -S -1 2>/dev/null \
    | grep -oP '5h:\K[0-9]+(?=%)' | tail -1 || echo "")
  raw=$(tmux capture-pane -t "$pilot_win" -p -S -1 2>/dev/null \
    | grep -oP '5h:[0-9]+%\(\K[^\)]+' | tail -1 || echo "")
  # フォールバック: full pane から取得
  if [[ -z "$pct" && -z "$raw" ]]; then
    pct=$("$(git rev-parse --show-toplevel)/plugins/session/scripts/session-comm.sh" capture "$pilot_win" 2>/dev/null \  # cross-plugin reference
      | grep -oP '5h:\K[0-9]+(?=%)' | tail -1 || echo "")
    raw=$("$(git rev-parse --show-toplevel)/plugins/session/scripts/session-comm.sh" capture "$pilot_win" 2>/dev/null \  # cross-plugin reference
      | grep -oP '5h:[0-9]+%\(\K[^\)]+' | tail -1 || echo "")
  fi
  if [[ -z "$pct" && -z "$raw" ]]; then
    echo "[BUDGET-LOW] WARN: budget 情報を取得できません。" >&2
    echo "pct=-1 cycle_min=-1 remaining_min=-1"
    return 0
  fi
  local cycle_min=-1
  if [[ "$raw" =~ ^([0-9]+)h([0-9]+)m$ ]]; then
    cycle_min=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
  elif [[ "$raw" =~ ^([0-9]+)h$ ]]; then
    cycle_min=$(( ${BASH_REMATCH[1]} * 60 ))
  elif [[ "$raw" =~ ^([0-9]+)m$ ]]; then
    cycle_min=${BASH_REMATCH[1]}
  fi
  local remaining_min=-1
  if [[ "${pct:-}" =~ ^[0-9]+$ ]]; then
    remaining_min=$(( 300 * (100 - pct) / 100 ))
  fi
  echo "pct=${pct:-0} cycle_min=${cycle_min} remaining_min=${remaining_min}"
}

check_budget_low() {
  local pilot_win="${1:-}"
  local threshold_remaining="${BUDGET_THRESHOLD_REMAINING}"
  local threshold_cycle="${BUDGET_THRESHOLD_CYCLE}"
  local info pct cycle_min remaining_min alert=false
  info=$(get_budget_info "$pilot_win")
  # eval を避け、パラメータ展開で個別抽出する（インジェクション回避）
  pct="${info#*pct=}"; pct="${pct%% *}"
  cycle_min="${info#*cycle_min=}"; cycle_min="${cycle_min%% *}"
  remaining_min="${info#*remaining_min=}"; remaining_min="${remaining_min%% *}"
  [[ "$pct" =~ ^-?[0-9]+$ ]] || pct=-1
  [[ "$cycle_min" =~ ^-?[0-9]+$ ]] || cycle_min=-1
  [[ "$remaining_min" =~ ^-?[0-9]+$ ]] || remaining_min=-1
  # 軸1 (consumption-based): token 残量 ≤ threshold_remaining_minutes
  if [[ "$remaining_min" -ge 0 && "$remaining_min" -le "$threshold_remaining" ]]; then alert=true; fi
  # 軸2 (cycle-based): cycle reset wall-clock ≤ threshold_cycle_minutes
  if [[ "$cycle_min" -ge 0 && "$cycle_min" -le "$threshold_cycle" ]]; then alert=true; fi
  if [[ "$alert" == "true" ]]; then
    echo "[BUDGET-LOW] 5h budget: token残量 ${remaining_min}分 (${pct}% 消費), cycle reset まで ${cycle_min}分。安全停止シーケンスを開始します。"
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
     "cycle_reset_minutes_at_pause": 26,
     "expected_reset_at": "<paused_at + cycle_reset_minutes_at_pause>",
     "auto_resume_via": "schedulewakeup",
     "paused_workers": ["ap-569", "ap-570"],
     "orchestrator_pid": 12345
   }
   ```
   **注意**: `(YYm)` = `cycle_reset_minutes_at_pause` = cycle reset までの wall-clock（分）。reset 後に 5h budget 100% 完全回復（[不変条件 Q](../../refs/ref-invariants.md#invariant-q)）。
4. ScheduleWakeup で `cycle reset まで Z分（reset 後に 5h budget 100% 完全回復）`。`delaySeconds = (YYm) × 60 + 300`（cycle reset + 5 分余裕）

**再開シーケンス（Step 0 の budget-pause.json 復帰パスで実行）:**

1. 各 `paused_workers` の `session-state.sh state <window>` → `idle` or `input-waiting` 確認
2. Pilot window 状態確認
3. orchestrator の再起動（`session-comm.sh inject` で orchestrator 起動コマンド送信）
4. 各 Worker に `session-comm.sh inject` で再開指示送信
5. 全 Worker が `processing` 状態に遷移したことを確認
6. `budget-pause.json` の `status` を `resumed` に更新

---

## [PERMISSION-PROMPT] — Worker permission prompt 検知

**検知対象**: Worker window に Claude Code の permission prompt（`1. Yes, proceed` / `2. No, and tell Claude what to do differently` / `3. Yes, and allow always` / `Interrupted by user`）が出現した場合

**閾値**: 即時（permission prompt は自動解消しないため、thinking 中でも emit する）

**検知方法**: `cld-observe-any` の `[PERMISSION-PROMPT]` event（`BUDGET-LOW` emit ブロック直後・thinking guard より前に配置）

**regex**: `^([1-9]\. (Yes, proceed|Yes, and allow|No, and tell)|Interrupted by user)`

**observer が PERMISSION-PROMPT event を受信した際の振る舞い（Issue #973 以降）:**

1. ログ出力: `[PERMISSION-PROMPT] window=<win> に permission prompt 検出`
2. `cld-observe-any` が `prompt_context`（capture-pane 50行, strip_ansi, max 8KB）と `options`（メニュー選択肢）を event json に付加して emit する
3. `soft_deny_match.py` で soft_deny ルール（`soft-deny-rules.md` SSoT）と照合する
4. **分岐**:
   - **no-match** → Layer 0 Auto: `session-comm.sh inject $WIN "1" --force` で自動承認
   - **match-confirm** → STOP + Layer 1 Confirm 昇格（AskUserQuestion で文脈提示）
   - **match-escalate** → STOP + Layer 2 Escalate 昇格（Pilot escalation 通知）
5. 全分岐で InterventionRecord を `.observation/` に記録する

**注意**: false positive 防止のため、`^[1-9]\.` + 具体語（`Yes, proceed|Yes, and allow|No, and tell`）による行頭マッチが必須。`Interrupted by user` は別 alternation として処理する（行頭英字のため `[1-9]\.` prefixなし）。

**参照**: `pitfalls-catalog.md §4.7`（permission prompt pitfall 対処手順）

---

## `cld-observe-any` 標準スニペット（推奨実装）

既存の Monitor tool + cld-observe-loop と**補完関係**にある。置換ではなく併用する。

### 基本起動（Worker 群監視）

```bash
# Monitor tool と cld-observe-any を必ず同時起動（SKILL.md §supervise ポリシー踏襲）
# pattern '(ap-|wt-co-).*' で Worker window と Pilot window の両方を対象にする（Issue #948 修正）
"$(git rev-parse --show-toplevel)/plugins/session/scripts/cld-observe-any" \  # cross-plugin reference
  --pattern '(ap-|wt-co-).*' \
  --interval 180 \
  --stagnate-sec 600 \
  --budget-threshold 15 \
  --event-dir .supervisor/events \
  --notify-dir /tmp/claude-notifications
```

### Pilot/co-issue 等の対話型セッション監視

```bash
# 特定 window を多指標 AND 条件で監視
"$(git rev-parse --show-toplevel)/plugins/session/scripts/cld-observe-any" \  # cross-plugin reference
  --window "$PILOT_WINDOW" \
  --interval 30 \
  --complete-regex "PHASE_COMPLETE" \
  --complete-require-cmd-echo "gh issue edit [0-9]+ --add-label refined" \
  --stagnate-sec 300
```

### 単発チェック（--once）

```bash
# 現在状態を一回評価して exit（inline 判定に使用）
result=$("$(git rev-parse --show-toplevel)/plugins/session/scripts/cld-observe-any" \  # cross-plugin reference
  --window "$WIN" --once 2>/dev/null)
echo "event: $result"
```

### Monitor tool 連携経路（方式 A: 共有 logfile tail）

cld-observe-any stdout を共有 logfile に `tee -a` で redirect し、Monitor tool がその logfile を `tail -F` で監視する正規経路（**方式 A**）。**Wave 起動時は本連携経路を使用すること**（SHOULD）。方式 B（event-dir polling）/ 方式 C（FIFO）は将来検討項目として `pitfalls-catalog.md §4.11` に記録。

**起動例（方式 A）**:
```bash
# cld-observe-any stdout を共有 logfile に redirect（方式 A 正規パス）
"$(git rev-parse --show-toplevel)/plugins/session/scripts/cld-observe-any" \  # cross-plugin reference
  --pattern '(ap-|wt-co-).*' \
  --interval 180 \
  --stagnate-sec 600 \
  --budget-threshold 15 \
  --event-dir .supervisor/events \
  --notify-dir /tmp/claude-notifications \
  2>&1 | tee -a .supervisor/cld-observe-any.log &

# Monitor tool 側は logfile を tail -F で監視
until [[ -s .supervisor/cld-observe-any.log ]]; do sleep 1; done
tail -F .supervisor/cld-observe-any.log
```

**各 event の Monitor tool `pattern` フィールド（そのまま貼り付け可）**:

[MENU-READY] — pattern: `\[MENU-READY\]`（Enter to select 表示。OBSERVER_AUTO_INJECT_ENABLE=1 で自動 inject）
[REVIEW-READY] — pattern: `\[REVIEW-READY\]`（Submit answers 表示。inject で submit）
[FREEFORM-READY] — pattern: `\[FREEFORM-READY\]`（[y/N]/Press up 表示。inject で応答）
[BUDGET-LOW] — pattern: `\[BUDGET-LOW\]`（budget 残量 ≤ 閾値。停止シーケンス参照）
[STAGNATE-N] — pattern: `\[STAGNATE-`（log age ≥ N 秒。STAGNATE 介入フロー参照）

**参照**: `pitfalls-catalog.md §4.11`（方式 A 運用上の懸念と連携落とし穴）

---

### イベント種別と対応アクション

| イベント | 説明 | 対応 |
|---|---|---|
| `[PANE-DEAD]` | pane 終了 | Worker 消失確認 → 後処理 |
| `[ERROR-STATE]` | Traceback/command not found | ログ確認 → 自動修復または Escalate |
| `[BUDGET-LOW]` | budget 残量 ≤ 閾値 | 停止シーケンス（BUDGET-LOW 定義参照） |
| `[PERMISSION-PROMPT]` | permission prompt 出現 | soft_deny 非該当時は Layer 0 Auto inject、該当時は Layer 1/2 昇格 |
| `[PHASE-COMPLETE]` | フェーズ完了フレーズ検知 | 次 Wave 移行 |
| `[REVIEW-READY]` | Submit answers 表示 | inject で submit |
| `[MENU-READY]` | Enter to select 表示 | `OBSERVER_AUTO_INJECT_ENABLE=1` 設定時は daemon が自動 inject、未設定時は observer 手動 inject（#1145, Option A） |
| `[FREEFORM-READY]` | [y/N]/Press up 表示 | inject で応答 |
| `[STAGNATE-N]` | log age ≥ N 秒 | STAGNATE 介入フロー |

---

## Hybrid 検知ポリシー（イベントファイルプライマリ — MUST）

各チャネルで `.supervisor/events/` 配下のイベントファイルを**プライマリ**として確認し、不在の場合のみ polling にフォールバックする:

| チャネル | プライマリ（イベントファイル） | フォールバック（polling） |
|---|---|---|
| **STAGNATE** | `.supervisor/events/heartbeat-*` mtime が `AUTOPILOT_STAGNATE_SEC`（デフォルト 600s）以上古ければ `[STAGNATE]` | `.autopilot/issues/issue-*.json` / `.supervisor/working-memory.md` / `.autopilot/checkpoints/*.json` の mtime |
| **INPUT-WAIT** | `.supervisor/events/input-wait-*` が存在する場合、即時 `[INPUT-WAIT]` | `session-state.sh state <window>` が `input-waiting` を返す場合 |
| **NON-TERMINAL** | `.supervisor/events/skill-step-*` の `skill` フィールドのタイムスタンプが 2 分超で chain 未遷移 → `[NON-TERMINAL]` | `session-comm.sh capture` + `>>> 実装完了:` grep |
| **WORKERS** | `.supervisor/events/session-end-*` が存在する場合、`[WORKERS]` に追記。**読み出し後に個別削除（SHALL）**: `rm -f .supervisor/events/session-end-<session_id>` | — |
| **PILOT-IDLE / PHASE-DONE** | イベントファイル対象外 | 既存 polling のまま |
| **MENU-READY** | `.supervisor/events/MENU-READY-*.json`（`.json` 拡張子） | 方式 A: `.supervisor/cld-observe-any.log` を `tail -F` で監視し `\[MENU-READY\]` grep |
| **REVIEW-READY** | `.supervisor/events/REVIEW-READY-*.json`（`.json` 拡張子） | 方式 A: `.supervisor/cld-observe-any.log` を `tail -F` で監視し `\[REVIEW-READY\]` grep |
| **FREEFORM-READY** | `.supervisor/events/FREEFORM-READY-*.json`（`.json` 拡張子） | 方式 A: `.supervisor/cld-observe-any.log` を `tail -F` で監視し `\[FREEFORM-READY\]` grep |

---

## [PILOT-PHASE-COMPLETE] — Pilot 内部 chain の Phase 完了検知

> **追加背景（Issue #948）**: Pilot 内部 chain（別 tmux window `ap-*` を作らない flow）完遂時、
> 従来チャネルは Worker spawn 前提であったため、Pilot-only の完了 signal を検知できなかった。

**検知対象**: Pilot window から emit される Phase/Issue 完了 signal

**閾値**: 即時

**regex**:
```bash
PILOT_PHASE_COMPLETE_REGEX='(\[orchestrator\] Phase [0-9]+ 完了|\{"signal": "PHASE_COMPLETE"|\[merge-gate\] Issue #[0-9]+: マージ完了|\[orchestrator\] cleanup: Issue #[0-9]+|>>> Phase [A-Z]+ Wave [0-9]+ step [0-9]+ 完遂)'
```

**Signal 一覧**: `refs/pilot-completion-signals.md` の「PILOT-PHASE-COMPLETE」セクションを参照。

**bash スニペット（Monitor tool 向け）:**
```bash
# PILOT-PHASE-COMPLETE: Pilot 内部 chain の Phase 完了を検知
pattern='(\[orchestrator\] Phase [0-9]+ 完了|\{"signal": "PHASE_COMPLETE"|\[merge-gate\] Issue #[0-9]+: マージ完了|\[orchestrator\] cleanup: Issue #[0-9]+|>>> Phase [A-Z]+ Wave [0-9]+ step [0-9]+ 完遂)'
description='[PILOT-PHASE-COMPLETE] Pilot 内部 chain の Phase 完了を検知しました'
```

---

## [PILOT-ISSUE-MERGED] — Issue の PR merge 完了検知

**検知対象**: `[auto-merge] Issue #<N>: merge 成功` signal

**閾値**: 即時

**regex**:
```bash
PILOT_ISSUE_MERGED_REGEX='\[auto-merge\] Issue #[0-9]+: merge 成功'
```

**bash スニペット:**
```bash
# PILOT-ISSUE-MERGED: Issue の PR merge 完了を検知
pattern='\[auto-merge\] Issue #[0-9]+: merge 成功'
description='[PILOT-ISSUE-MERGED] Issue の PR が merge されました'
```

**PR merge 確認クエリ**: `refs/pilot-completion-signals.md` の「PR merge 確認クエリ」セクションを参照。

---

## [PILOT-WAVE-COLLECTED] — Wave 収集完了検知

**検知対象**: `[wave-collect] Wave <N> サマリを生成しました: <path>` signal

**閾値**: 即時

**regex**:
```bash
PILOT_WAVE_COLLECTED_REGEX='\[wave-collect\] Wave [0-9]+ サマリを生成しました'
```

**bash スニペット:**
```bash
# PILOT-WAVE-COLLECTED: Wave 収集完了を検知
pattern='\[wave-collect\] Wave [0-9]+ サマリを生成しました'
description='[PILOT-WAVE-COLLECTED] Wave 収集が完了しました。次 Wave の準備を開始してください。'
```

---

## [CO-EXPLORE-COMPLETE] — co-explore 完遂検知（Layer 0 Auto）

> **追加背景（Issue #1085）**: co-explore 完遂後の next-step postpone 判断 error（Wave U incident 1）。
> co-explore Worker は tmux pane に completion signal を emit しない構造のため、
> `.explore/<N>/summary.md` 生成を filesystem で直接検知するチャネルを新設する。

**検知対象**: `.explore/<N>/summary.md` の新規ファイル生成（co-explore 完遂の physical artifact）

**閾値**: 即時（ファイル生成検知後、5 分以内に next-step spawn）

**介入層**: Layer 0 Auto（SU-7 に従う）

**bash スニペット（Monitor tool 向け）:**

```bash
# CO-EXPLORE-COMPLETE: .explore/<N>/summary.md 生成を検知（co-explore 完遂用）
# Layer 0 Auto: 検知後 5 分以内に next-step を自律 spawn する
check_co_explore_complete() {
  local explore_dir="${1:-.explore}"
  local marker_file="${2:-.supervisor/co-explore-last-check}"
  local now
  now=$(date +%s)

  # .explore/<N>/summary.md の存在確認（マーカーより新しいファイルを検索）
  local found
  if [[ -f "$marker_file" ]]; then
    found=$(find "${explore_dir}" -name "summary.md" -newer "$marker_file" 2>/dev/null | head -1)
  else
    found=$(find "${explore_dir}" -name "summary.md" 2>/dev/null | head -1)
  fi

  if [[ -n "$found" ]]; then
    echo "[CO-EXPLORE-COMPLETE] co-explore 完遂を検知: ${found}"
    echo "[CO-EXPLORE-COMPLETE] next-step を 5 分以内に自律 spawn すること（Layer 0 Auto）"
    echo "$now" > "$marker_file"
    return 1
  fi

  echo "$now" > "$marker_file"
  return 0
}
```

**Signal 詳細**: `refs/pilot-completion-signals.md` の「CO-EXPLORE-COMPLETE」セクションを参照。

---

## window 存在確認の正しい方法（has-session 誤用禁止）

> **重要（Issue #948, R6）**: `tmux has-session -t <window-name>` は window 存在確認として機能しない。
> `has-session` の `-t` は session specifier であり、window 名を渡しても常に false を返す。
> これにより `[WINDOW-GONE]` false positive が 1 分毎に発火した実例がある。

### 誤り（MUST NOT）

```bash
# NG: has-session の -t は session specifier。window 名を渡しても常に false
tmux has-session -t wt-co-explore-114550  # → 1（window が実在しても常に失敗）
```

### 正しい方法

**方法 A（推奨 — session 不明時）**: 全セッションの window 一覧から検索

```bash
# 方法 A: tmux list-windows -a で全セッションの window を検索
tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -Fxq "wt-co-explore-114550" \
  && echo "alive" || echo "gone"
```

**方法 B（session 名判明時）**: 特定 session の window 一覧から検索

```bash
# 方法 B: 特定 session の window 一覧から検索（session 名が分かる場合）
tmux list-windows -t twill-ipatho1 -F '#{window_name}' 2>/dev/null \
  | grep -Fxq "wt-co-explore-114550" && echo "alive" || echo "gone"
```

**方法 C（window_id 取得）**: display-message で window_id を取得

```bash
# 方法 C: display-message で window_id を取得（存在すれば非空文字列）
tmux display-message -t "twill-ipatho1:wt-co-explore-114550" -p '#{window_id}' 2>/dev/null \
  && echo "alive" || echo "gone"
```

**共通ライブラリ**: `${CLAUDE_PLUGIN_ROOT}/scripts/lib/observer-window-check.sh` に `_check_window_alive()` として実装済み。

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/observer-window-check.sh"
_check_window_alive "wt-co-explore-114550" && echo "alive" || echo "gone"
# session 名を指定する場合
_check_window_alive "wt-co-explore-114550" "twill-ipatho1" && echo "alive" || echo "gone"
```

---

## [IDLE-COMPLETED] — completion 後 idle 確定 (cleanup-trigger) (Issue #1117)

**検知対象**: completion phrase 確認後、60s 以上 idle 継続した controller/Worker window

**閾値**: debounce 60s（`IDLE_COMPLETED_DEBOUNCE_SEC` env var で override 可能）

**介入層**: Confirm（Layer 1）— observer が kill 候補として判断し、`tmux kill-window` を実行

**対象 window pattern**: `(ap-|wt-|coi-).*`（co-issue orchestrator が `coi-` を spawn することを確認 — #1117）

**completion phrase regex (SSOT — AC-1)**:

行単位（`grep -qE`）で機能する。`次のステップ:` は A2 (LLM idle) + A3 (log mtime stale) + A4 (no menu) の他条件 AND によって false positive を抑制する前提:

```
(refined ラベル付与|Status=Refined|nothing pending|recap: Goal|>>> 実装完了|Phase 4 完了|merge-gate.*成功|spec-review marker cleanup|explore-summary saved|\.explore/[0-9]+/summary\.md|次のステップ:|co-autopilot complete|Wave [0-9]+ co-autopilot complete|hand control back to su-observer|observer 側で次の|Step [0-9]+ 完了処理|orchestrator --summary（done=)
```

*注: このコードブロックは `observer-idle-check.sh:14` の SSOT と同期した説明用コピー（Issue #1375 で co-autopilot 完了 phrase 6件追加）。実行時参照は `observer-idle-check.sh` のみ。*

**実装の分離**:
- `_check_idle_completed()` → `skills/su-observer/scripts/lib/observer-idle-check.sh` (stateless 純粋関数)
- `IDLE_COMPLETED_TS[$WIN]` 連想配列 → `cld-observe-any` メインループスコープで管理
- `evaluate_window()` は stateless 設計を維持（連想配列を内部に持たない）
- **LLM indicator SSOT**: `plugins/session/scripts/lib/llm-indicators.sh` が `LLM_INDICATORS` 配列の唯一の定義源（#1374）。`cld-observe-any`・`issue-lifecycle-orchestrator.sh`・`observer-idle-check.sh` の3ファイルが `source` 経由で参照する

**既存 channel との関係**:
- `[PHASE-DONE]` / `[PILOT-PHASE-COMPLETE]` 等は completion phrase 1 回 emit（一過性）
- `[IDLE-COMPLETED]` は debounce 経た idling 確定状態を **60s ごとに継続 emit**（observer が kill するまで繰り返す）
- S-1 IDLE の「放置可」→「cleanup-trigger」への格上げ条件（単なる IDLE とは区別）

**pitfalls-catalog.md §4.10 との関係**:
- S-1 IDLE（一時的、継続観察）
- S-1 IDLE + completion phrase 60s 安定 = cleanup 対象 → `[IDLE-COMPLETED]` 発火

**Monitor tool snippet (多指標 AND 判定):**

```bash
# 前提: cld-observe-any メインループスコープに declare -A IDLE_COMPLETED_TS を宣言
# この snippet は evaluate_window() 外のメインループ内に配置

source "skills/su-observer/scripts/lib/observer-idle-check.sh"

for WIN in "${TARGET_WINS[@]}"; do
    # A1: pane content 取得
    PANE_CONTENT=$(tmux capture-pane -t "$WIN" -p -S -60 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
    NOW=$(date +%s)
    FIRST_SEEN="${IDLE_COMPLETED_TS[$WIN]:-0}"

    if _check_idle_completed "$PANE_CONTENT" "$FIRST_SEEN" "$NOW" "${IDLE_COMPLETED_DEBOUNCE_SEC:-60}"; then
        echo "[IDLE-COMPLETED] $WIN: completion confirmed, kill candidate"
        IDLE_COMPLETED_TS[$WIN]=$NOW  # 60s ごとに継続 emit
    else
        [[ "${IDLE_COMPLETED_TS[$WIN]:-0}" -eq 0 ]] && \
            echo "$PANE_CONTENT" | grep -qE "$IDLE_COMPLETED_PHRASE_REGEX" && \
            IDLE_COMPLETED_TS[$WIN]=$NOW
    fi
done
```

**co-autopilot 完了 phrase（Issue #1375 追加）**: co-autopilot 実行中の Pilot が発する完了 phrase を追加。Wave recap や Step 完了時の auto-kill 不発火を修正:
- `co-autopilot complete` — Pilot recap 末尾の汎用完了マーカー
- `hand control back to su-observer` — 次 Wave 委譲の完了宣言
- `observer 側で次の` — Wave N 完了後の制御委譲
- `Step [0-9]+ 完了処理` — Step N 完了処理の汎用パターン
- `orchestrator --summary（done=` — orchestrator サマリ出力の完了マーカー

**自動 kill オプション**: `IDLE_COMPLETED_AUTO_KILL=1`（opt-in、Issue #1132）で `[IDLE-COMPLETED]` 発火時に `tmux kill-window` を自動実行（Layer 0 Auto）。デフォルトは alert のみ（Layer 1 Confirm）。

**自動 next-spawn オプション**: `IDLE_COMPLETED_AUTO_NEXT_SPAWN=1`（opt-in、Issue #1155）で kill 成功後に `.supervisor/wave-queue.json` を参照して次 Wave を自動 spawn（`AUTO_KILL=1` と独立評価、両方設定が必要）。`AUTO_NEXT_SPAWN=dry-run` で spawn コマンド echo のみ（実行なし）。未設定時は kill-only（#1132 既存動作維持）。

---

## [MONITOR-REARM] — controller spawn 完了後の Monitor 再 arm trigger（Issue #1186）

> **追加背景（Issue #1186, doobidoo Hash 3ecbfbc2）**: `spawn-controller.sh` が新 controller window を spawn した直後、
> observer LLM は旧 channel を監視し続けて新 window を捕捉できない問題（30+ 分 silent incident）。
> spawn 完了直前に stdout へ emit することで observer に Monitor 再 arm を促す。

**検知対象**: `spawn-controller.sh` stdout の emit 文（exec/cld-spawn 呼出直前）

**emit 文**: `>>> Monitor 再 arm 必要: <window-name>`

**regex パターン（Monitor tool / cld-observe-any --pattern 向け）:**

```
>>> Monitor 再 arm 必要: [^\n]+
```

**受信経路**（方式 A 推奨）: `spawn-controller.sh` 出力を `tee -a .supervisor/cld-observe-any.log` で共有 logfile に redirect、Monitor tool が `tail -F` で監視。

```bash
# spawn 呼び出し例（方式 A）
bash spawn-controller.sh co-issue "$PROMPT_FILE" --window-name "$WINDOW" \
  2>&1 | tee -a .supervisor/cld-observe-any.log
```

**observer の対応（Layer 0 Auto）**:
1. `>>> Monitor 再 arm 必要: <window-name>` を検知する
2. `<window-name>` を取得し、Monitor tool の監視対象を新 window に切り替える
3. または `cld-observe-any --pattern ">>> Monitor 再 arm 必要"` で検知後、新 window へ re-arm

**介入層**: Layer 0 Auto（既存 Monitor 再設定は observer 自律判断範囲内）

---

## controller type 別 primary completion signal mapping

su-observer が controller window の完了を判定する際に参照する primary signal の SSOT。
各 controller type は primary / secondary / tertiary の優先順で completion を検知する。
Signal regex の詳細は `pilot-completion-signals.md` を参照すること（MUST）。

| controller type | primary | secondary | tertiary |
|---|---|---|---|
| co-autopilot | `[PILOT-WAVE-COLLECTED]` | `[wave-collect] Wave <N> サマリを生成しました` | `[IDLE-COMPLETED]` |
| co-issue (refine) | `[IDLE-COMPLETED]` | `Status=Refined` regex | window kill (`IDLE_COMPLETED_AUTO_KILL=1`) |
| co-issue (新規) | `>>> Issue #N 作成完了` | `[IDLE-COMPLETED]` | window kill |
| co-explore | `[CO-EXPLORE-COMPLETE]` | `>>> explore 完了:` | `[IDLE-COMPLETED]` |
| co-architect | `>>> arch-phase-review PASS` | `[arch-merge]` | `[IDLE-COMPLETED]` |
| co-self-improve | (TBD) | (TBD) | `[STAGNATE]` |

---

## Wave 種別ごとのチャネル選択ガイド

| Wave 種別 | 推奨チャネル |
|---|---|
| co-autopilot 実行中（全般） | INPUT-WAIT + STAGNATE + WORKERS + BUDGET-LOW + **PILOT-PHASE-COMPLETE** |
| Phase 実行中（Worker 並列） | INPUT-WAIT + WORKERS + PHASE-DONE |
| 長時間 Pilot 処理（Pilot-only chain） | PILOT-IDLE + NON-TERMINAL + **PILOT-PHASE-COMPLETE** + BUDGET-LOW |
| Issue merge 監視 | **PILOT-ISSUE-MERGED** + STAGNATE |
| Wave 完了監視 | **PILOT-WAVE-COLLECTED** + STAGNATE |
| 並列 controller 運用（refine/explore 群） | **IDLE-COMPLETED** + INPUT-WAIT + WORKERS |
| デバッグ・問題調査 | INPUT-WAIT + STAGNATE（最小セット） |

---

## Monitor task 起動テンプレート（起動時 SOP 用）

> **差分明示**: 上記 §`cld-observe-any` 標準スニペット（L499-558）は推奨実装パターン。
> 本節は Step 0 step 6.5「Monitor task 起動 MUST」用の **起動時 SOP テンプレート**であり、
> observer LLM が「忘れる」リスクを排除するための構造化手順を提供する。
> `step0-monitor-bootstrap.sh` が stdout に emit するコマンドをそのまま Monitor tool で実行すること。

### 起動手順（Step 0 step 6.5 の実行内容）

```bash
# 1. bootstrap script を実行して起動コマンドを確認
bash "${CLAUDE_PLUGIN_ROOT}/skills/su-observer/scripts/step0-monitor-bootstrap.sh"

# 2. daemon が未起動の場合: emit されたコマンドを Monitor tool で実行
#    (cld-observe-any daemon + tail -F .supervisor/cld-observe-any.log)
```

### daemon 既存検知（pgrep -f パターン踏襲）

```bash
# daemon 起動済みチェック
bash "${CLAUDE_PLUGIN_ROOT}/skills/su-observer/scripts/step0-monitor-bootstrap.sh" --check
# exit 0: RUNNING (起動コマンド emit をスキップ)
# exit 1: NOT_RUNNING (起動コマンドを emit して Monitor tool で実行)
```

### 定期 audit pattern（Step 1 supervise loop 内 MUST）

5 分ごとに全 `ap-/wt-/coi-` window に対し以下を実行し、menu/input-wait 状態を検知する:

```bash
# ANSI escape strip 必須（pitfalls-catalog.md §2.5 同様の制約）
tmux capture-pane -p | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Enter to select|^❯ [1-9]\.|Press up to edit queued'
```

**検知パターン**:
| パターン | 検知状況 |
|---|---|
| `Enter to select` | インタラクティブ選択メニュー待ち |
| `^❯ [1-9]\.` | 番号付きメニュー選択待ち |
| `Press up to edit queued` | キュー編集プロンプト待ち（orchestrator-side でも `queued_message_residual` pattern として自動検知・回復 — #1580） |
