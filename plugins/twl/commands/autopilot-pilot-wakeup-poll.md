---
type: atomic
tools: [Bash, ScheduleWakeup]
effort: high
maxTurns: 50
---
# Pilot Wake-up Poll（autopilot-pilot-wakeup-poll）

ScheduleWakeup ベースの PHASE_COMPLETE 検知ループ。Steps B1–B5 に相当。bootstrap 後に呼び出す。

## Step B: ScheduleWakeup(300) — PHASE_COMPLETE 能動確認ループ

bootstrap 起動後、**ScheduleWakeup(300)** で 5 分間隔の wake-up サイクルを開始する。bash while ループではなく ScheduleWakeup を必ず使用すること（Bash タイムアウト回避）。

**wake-up 時の確認手順（MUST）:**

### B1. PHASE_COMPLETE 確認

```bash
grep -c "PHASE_COMPLETE" "$_ORCH_LOG" 2>/dev/null || grep -c "PHASE_COMPLETE" "${AUTOPILOT_DIR}/trace/orchestrator-phase-${PHASE_NUM}"-*.log 2>/dev/null
```

出力が `1` 以上 → PHASE_COMPLETE 受信として呼出元の Step 4.5 へ制御を返す。

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
   - PHASE_COMPLETE 相当として呼出元の Step 4.5 へ進む（orchestrator からの signal を待たない）
3. **stagnation Worker（`updated_at` が 15 分以上古い）が存在する**場合:
   - `session-comm.sh inject-file` で詳細状況を送信して回復を試みる
   - ScheduleWakeup(600) で 10 分の猶予をスケジュール
4. **猶予後も stagnation が継続**する場合:
   - 当該 Worker を failed として `python3 -m twl.autopilot.state write ... --set "status=failed"` で記録
   - 残り Worker が全 terminal なら Step 4.5 へ進む

Silence heartbeat 検知が必要な場合は `commands/autopilot-pilot-wakeup-heartbeat.md` を Read → 実行すること。

## 出力

PHASE_COMPLETE 検知後、呼出元（co-autopilot Step 4）に制御を返す。

<!-- NOTE: Pilot 用 atomic グループの一員。設計原則 P1 (ADR-010) 参照。 -->
