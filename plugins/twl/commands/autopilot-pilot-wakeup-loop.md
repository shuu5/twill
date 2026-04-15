---
type: atomic
tools: [Bash, ScheduleWakeup]
effort: high
maxTurns: 50
---
# Pilot Wake-up Loop（autopilot-pilot-wakeup-loop）

ScheduleWakeup ベースの PHASE_COMPLETE 検知ループ。orchestrator の起動から PHASE_COMPLETE 受信まで Pilot の polling 責務を担う。stagnation 検知・Silence heartbeat・状況精査モードを包含する。

## 前提変数（呼出元から引き継ぐ MUST）

- `$AUTOPILOT_DIR`: state file ディレクトリの SSOT
- `$PROJECT_DIR`: bare repo の親ディレクトリ
- `$PHASE_NUM`: 現在の Phase 番号
- `$REPOS_ARG`: クロスリポジトリ引数（省略可）

## Step A: orchestrator 起動（nohup/disown）

Pilot の Bash context 外で持続実行するため **nohup/disown** を使用すること（不変条件 M — Pilot timeout/cancel による chain 停止防止）。`--session` には `$AUTOPILOT_DIR` を使った絶対パスを指定すること（相対パス・セッション ID 直接渡しは不可）:

```bash
mkdir -p "${AUTOPILOT_DIR}/trace"
_ORCH_LOG="${AUTOPILOT_DIR}/trace/orchestrator-phase-${PHASE_NUM}.log"
cd "${PROJECT_DIR}/main" 2>/dev/null || cd "${PROJECT_DIR}" || true
nohup bash autopilot-orchestrator.sh \
  --plan "${AUTOPILOT_DIR}/plan.yaml" \
  --phase "$PHASE_NUM" \
  --session "${AUTOPILOT_DIR}/session.json" \
  --project-dir "$PROJECT_DIR" \
  --autopilot-dir "$AUTOPILOT_DIR" \
  ${REPOS_ARG:+"$REPOS_ARG"} \
  >> "$_ORCH_LOG" 2>&1 &
disown
_ORCH_PID=$!
echo "[autopilot-pilot-wakeup-loop] orchestrator PID=${_ORCH_PID} 起動 (nohup) → ログ: ${_ORCH_LOG}" >&2
```

## Step B: ScheduleWakeup(300) — PHASE_COMPLETE 能動確認ループ

orchestrator 起動後、**ScheduleWakeup(300)** で 5 分間隔の wake-up サイクルを開始する。bash while ループではなく ScheduleWakeup を必ず使用すること（Bash タイムアウト回避）。

**wake-up 時の確認手順（MUST）:**

### B1. PHASE_COMPLETE 確認

```bash
grep -c "PHASE_COMPLETE" "$_ORCH_LOG" 2>/dev/null
```

出力が `1` 以上 → PHASE_COMPLETE 受信として Step C（呼出元の Step 4.5）へ制御を返す。

### B2. 未完了の場合 — Worker 状態確認

全 Worker の state file を読んで `status` と `updated_at` を確認する:

```bash
python3 -m twl.autopilot.state read \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "<N>" --field status
python3 -m twl.autopilot.state read \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "<N>" --field updated_at
```

`updated_at` が現在時刻から `AUTOPILOT_STAGNATE_SEC`（デフォルト 900 秒）以上古い Worker は **stagnation** とみなす。

### B2.5. Input-waiting 確認（MUST）

全 Worker の state file を読んで `input_waiting_detected` を確認する:

```bash
python3 -m twl.autopilot.state read \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "<N>" --field input_waiting_detected
```

値が非空なら以下を実行:
- `input_waiting_at` を読んで経過時間を計算する
- 経過時間 < 5 分: warn ログを残し、次の wake-up まで待機（自動復旧を期待）
- 経過時間 ≥ 5 分: `session-comm.sh inject-file` で状況確認メッセージを Worker に送信し、手動介入を促す
- 経過時間 ≥ 10 分: state に `escalation_requested=input_waiting_stall` を書き込み、su-observer の Monitor 介入を期待する

### B3. Stagnation 検知時

stall 状態の Worker を特定してログ出力し、次の ScheduleWakeup をスケジュールする前に `session-comm.sh inject-file` 経由で回復信号を送信する。

### B4. 次の wake-up をスケジュール（PHASE_COMPLETE 未検知の場合）

- 経過時間 < `MAX_WAIT_MINUTES`（30 分）: ScheduleWakeup(300) で再スケジュール
- 経過時間 ≥ `MAX_WAIT_MINUTES`: **状況精査モード**（Step B5）に入る

## Step B5: 状況精査モード（タイムアウト後 MUST）

30 分 (`MAX_WAIT_MINUTES`) を超過した場合、単純に再スケジュールせず以下を順番に確認する:

1. 全 Worker の `status` を列挙（running / merge-ready / done / failed の件数）
2. **全 Worker が terminal 状態**（merge-ready / done / failed のいずれか）の場合:
   - PHASE_COMPLETE 相当として Step C（呼出元の Step 4.5）へ進む（orchestrator からの signal を待たない）
3. **stagnation Worker（`updated_at` が 15 分以上古い）が存在する**場合:
   - `session-comm.sh inject-file` で詳細状況を送信して回復を試みる
   - ScheduleWakeup(600) で 10 分の猶予をスケジュール
4. **猶予後も stagnation が継続**する場合:
   - 当該 Worker を failed として `python3 -m twl.autopilot.state write ... --set "status=failed"` で記録
   - 残り Worker が全 terminal なら Step C へ進む

## Step C: Silence heartbeat（MUST）

Pilot は ScheduleWakeup ごとに全 Worker の `updated_at` を追跡する。**全 Worker の `updated_at` が 5 分以上無変化かつ PHASE_COMPLETE 未検知**の場合、以下を実行する:

1. 全 Worker window に対して `tmux capture-pane -t <window> -p -S -30` を実行する
2. 取得した pane_output に input-waiting パターンを手動検査する:
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

<!-- NOTE: Pilot 用 atomic (autopilot-pilot-precheck, autopilot-pilot-rebase, autopilot-multi-source-verdict) 経由であれば、PR diff stat / AC spot-check 等の能動評価は許容される。設計原則 P1 (ADR-010) 参照。 -->

## 出力

PHASE_COMPLETE 検知後、呼出元（co-autopilot Step 4）に制御を返す。orchestrator は JSON レポート（PHASE_COMPLETE）を trace ログに出力する。実装詳細（batch 分割・Worker 起動・ポーリング・merge-gate・skip 伝播 [不変条件 D]）は orchestrator が正典。Pilot LLM の責務は計画承認・retrospective・cross-issue 分析に限定。
