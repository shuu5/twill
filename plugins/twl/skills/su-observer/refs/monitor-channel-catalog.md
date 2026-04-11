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

---

## Wave 種別ごとのチャネル選択ガイド

| Wave 種別 | 推奨チャネル |
|---|---|
| co-autopilot 実行中（全般） | INPUT-WAIT + STAGNATE + WORKERS |
| Phase 実行中（Worker 並列） | INPUT-WAIT + WORKERS + PHASE-DONE |
| 長時間 Pilot 処理 | PILOT-IDLE + NON-TERMINAL |
| デバッグ・問題調査 | INPUT-WAIT + STAGNATE（最小セット） |
