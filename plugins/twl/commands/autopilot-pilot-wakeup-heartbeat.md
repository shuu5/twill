---
type: atomic
tools: [Bash]
effort: medium
maxTurns: 20
---
# Pilot Silence Heartbeat（autopilot-pilot-wakeup-heartbeat）

全 Worker の沈黙を検知し input-waiting パターンを調査する atomic。Step C に相当。`autopilot-pilot-wakeup-poll` から呼び出される。

## Step C: Silence heartbeat（MUST）

Pilot は ScheduleWakeup ごとに全 Worker の `updated_at` を追跡する。**全 Worker の `updated_at` が 5 分以上無変化かつ PHASE_COMPLETE 未検知**の場合、以下を実行する。`tmux capture-pane` を直接呼び出さず `session-comm.sh capture` 経由で `resolve_target()` バリデーション（`session:index` 形式 regex または bare-name exact-match）を再利用する:

1. 全 Worker window に対して以下を実行する:

   ```bash
   # 事前検証（iteration の外で 1 回のみ）
   SESSION_SCRIPTS="${CLAUDE_PLUGIN_ROOT}/../session/scripts"
   if [[ ! -x "${SESSION_SCRIPTS}/session-comm.sh" ]]; then
     echo "WARN: session-comm.sh not found at ${SESSION_SCRIPTS}。input-waiting 検知を skip します" >&2
     _SESSION_COMM_OK=0
   else
     _SESSION_COMM_OK=1
   fi

   # iteration 内（各 worker 独立評価）
   for window in "${WORKER_WINDOWS[@]}"; do
     if [[ "$_SESSION_COMM_OK" -eq 1 ]]; then
       pane_output=$("${SESSION_SCRIPTS}/session-comm.sh" capture "$window" --lines 30 2>/dev/null || echo "")
     else
       pane_output=""
     fi
     # pane_output 空なら input-waiting 検知 skip、stagnation/escalate 判定は不変
   done
   ```

   `session-comm.sh capture` は内部で `resolve_target()` を使い、window 名の validate（`session:index` 形式 regex または bare-name exact-match）を行ってから tmux capture-pane を実行する。失敗時（①window 名が `session:index` regex reject／②bare-name lookup で見つからない／③tmux エラー／④session-comm.sh ファイル不在）は `pane_output=""` として続行し input-waiting 検知（item 2）のみを skip する（stagnation 判定・Silence heartbeat の escalate 判定には影響しない）。各 worker の capture は独立して評価され、1 worker の失敗が他 worker に波及しない。

2. 取得した pane_output に input-waiting パターンを手動検査する（`session-comm.sh capture` の既定 `strip_ansi` 経由で ANSI ストリップ済み出力に対して実施する）:
   - Menu UI: `Enter to select`、`↑/↓ to navigate`、`❯ <数字>.`
   - Free-form: `よろしいですか[？?]`、`続けますか`、`進んでよいですか`、`[y/N]`

3. input-waiting を検知 → 当該 Worker の state file に書き込む（orchestrator が停止している可能性への補完）:
   ```bash
   python3 -m twl.autopilot.state write \
     --autopilot-dir "$AUTOPILOT_DIR" \
     --type issue --issue "<N>" --role pilot \
     --set "input_waiting_detected=<pattern_name>" \
     --set "input_waiting_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

4. input-waiting 未検知でも沈黙が継続 → su-observer escalate（state に `escalation_requested=silence_stall` を書き込み、su-observer の Monitor 介入を期待する）

**閾値 5 分の根拠**: `AUTOPILOT_STAGNATE_SEC`（デフォルト 900 秒）の約半分。input-waiting は stagnation より早く検知したいため。

<!-- NOTE: Pilot 用 atomic グループの一員。設計原則 P1 (ADR-010) 参照。session-comm.sh capture 経由の resolve_target() バリデーション再利用パターンは本ファイルに保持する。 -->
