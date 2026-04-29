# supervise 1 iteration — 必須並行チャンネル

co-autopilot を supervise している間、1 iteration で以下のチャンネルを並行実行しなければならない（SHALL）:

| チャンネル | 目的 | Worker spawn あり | Pilot-only chain | 閾値/間隔 |
|---|---|---|---|---|
| Monitor tool (Pilot) | Pilot window の tail streaming | MUST | MUST + **PILOT-PHASE-COMPLETE** filter | 随時 |
| `cld-observe-any --pattern '(ap-|wt-|coi-).*' --interval 180` | Worker 群 + Pilot window polling（co-issue `coi-` 含む — Issue #1117） | MUST | MUST（`wt-co-*` 必須） | 3 分 |
| `.supervisor/events/` イベントファイル + mtime 監視 | hook プライマリ / polling フォールバック | MUST | MUST | `AUTOPILOT_STAGNATE_SEC` デフォルト 600s |
| `heartbeat-watcher.sh` | 5 分 silence → 自動 capture-pane | SHOULD | **MUST**（Pilot-only では唯一の能動検知手段） | 5 分 |
| `session-comm.sh capture` (ad-hoc) | 実体確認 | 必要時 | 必要時 | 必要時 |
| `gh pr list` (Pilot 向け) | state.pr と実体の差分検知 | Wave 管理時 | Wave 管理時（`in:body #N` syntax 使用） | Wave 管理時 |
| `[BUDGET-LOW]` tmux status line budget 残量パース | budget 枯渇前の安全停止 | MUST | MUST | 残り 15 分 or 90% 消費 |
| `[PERMISSION-PROMPT]` cld-observe-any 検知 | Worker permission prompt stuck 検出（`refs/pitfalls-catalog.md §4.7` 起点） | MUST | MUST | 即時 |
| **`[IDLE-COMPLETED]`** cld-observe-any IDLE 確定検知 | completion phrase 60s 安定 window を cleanup-trigger として報告（Layer 1 Confirm） | SHOULD | SHOULD（並列 controller 運用時 MUST） | 60s debounce（`IDLE_COMPLETED_DEBOUNCE_SEC` で override）|

## cld-observe-any 使用例（Monitor tool と必ず同時起動）

```bash
# pattern '(ap-|wt-|coi-).*' で Worker window + Pilot window + co-issue orchestrator window を対象（Issue #1117 更新）
# 旧パターン '(ap-|wt-co-).*' は coi- window を見逃す（Issue #948 修正時は co-issue が wt- を使用していたため）
plugins/session/scripts/cld-observe-any \
  --pattern '(ap-|wt-|coi-).*' --interval 180 --stagnate-sec 600 \
  --budget-threshold 15 --event-dir .supervisor/events \
  --notify-dir /tmp/claude-notifications
```

## 状態判定：多指標 AND 条件（MUST）

`session-state.sh state` の単独使用を禁止する。セッション状態は以下の多指標 AND 条件で判定する:

- A1: `tmux capture-pane -p -S -60`
- A2: LLM indicator（Thinking/Brewing 等）
- A3: pipe-pane log mtime
- A4: pane_dead
- A5: `session-state.sh`（補助のみ）
- A6: status line budget 残量

**A2 LLM indicator が存在する場合、[PHASE-COMPLETE]/[REVIEW-READY]/[MENU-READY]/[FREEFORM-READY]/[STAGNATE] は絶対に emit しない。**

## [BUDGET-LOW] 検知・停止シーケンス

`PILOT_WINDOW=<win> scripts/budget-detect.sh` を実行する（exit 1 = BUDGET-LOW 発動）。
詳細ロジックは `refs/monitor-channel-catalog.md` の `[BUDGET-LOW]` セクションを参照。

## 起動手順（co-autopilot spawn 後）

```bash
PILOT_WINDOW=<win> scripts/budget-monitor-watcher.sh &
# heartbeat-watcher.sh: 5 分 silence → 自動 capture-pane（Issue #948, R4）
PILOT_WINDOW=<win> scripts/heartbeat-watcher.sh &  # scripts/ は skills/su-observer/scripts/
cld-observe-loop --pattern '(ap-|wt-|coi-).*' --interval 180
```

Monitor tool + cld-observe-any は必ず同時起動すること（SHALL）。どちらか一方のみの使用は禁止。
heartbeat-watcher.sh は co-autopilot spawn 直後に budget-monitor-watcher.sh と同時に起動すること（MUST）。

## Hybrid 検知ポリシー

各チャネルで `.supervisor/events/` 配下のイベントファイルをプライマリとして確認し、不在時のみ polling にフォールバックする。詳細は `refs/monitor-channel-catalog.md` の「Hybrid 検知ポリシー」セクションを参照。

## Heartbeat self-update 除外規約（MUST — Issue #1085）

### 問題

observer 自身の heartbeat 更新が heartbeat-watcher の silence 検知を reset してしまい、Pilot の真の idle/完遂 を能動 polling せずに fail-silent となる（Wave U Incident 3）。

### 規約

**MUST**: heartbeat-watcher.sh は observer 自身の heartbeat 更新を silence 検知の reset 対象外とすること。

- heartbeat ファイルの writer pid と watcher pid を区別し、observer self-update による reset を除外する
- Pilot の silence は **Pilot 側の heartbeat mtime または capture-pane の IDLE prompt** で独立して判定する
- observer 自身の heartbeat 更新は `observer self` フラグを付与し、watcher が識別できるようにする

```bash
# heartbeat self-update 除外: observer 自身の更新は silence reset 対象外
# heartbeat ファイルに writer_pid を JSON で記録し、watcher が observer 自身の更新を除外する
write_heartbeat() {
  local hb_file="${1:-.supervisor/events/heartbeat-observer}"
  echo "{\"ts\": $(date +%s), \"writer\": \"observer\", \"writer_pid\": $$}" > "$hb_file"
}

# watcher 側: writer=observer のファイルは Pilot silence 判定に使用しない
is_pilot_heartbeat() {
  local hb_file="$1"
  local writer
  writer=$(jq -r '.writer // "pilot"' "$hb_file" 2>/dev/null || echo "pilot")
  [[ "$writer" != "observer" ]]
}
```

### 能動 capture polling（Monitor task）規約（MUST — Issue #1085）

**MUST**: Pilot 監視時に **能動 capture polling（Monitor task）を起動** し、heartbeat-watcher の受動検知を補完すること。

- Monitor task は Pilot window の `tmux capture-pane` を能動的に polling し、IDLE prompt（`Saturated for`/`Worked for` + `>` プロンプト）を検出する
- heartbeat-watcher だけに依存してはならない（heartbeat が止まらなくても Pilot が実際には IDLE の場合がある）
- Monitor task は co-autopilot spawn 後に budget-monitor-watcher.sh と同時に起動すること

```bash
# 能動 capture polling (Monitor task): Pilot IDLE 判定
# heartbeat-watcher と必ず同時起動（MUST）
PILOT_WINDOW="${PILOT_WINDOW:-}"
while true; do
  if [[ -n "$PILOT_WINDOW" ]]; then
    pane_content=$(tmux capture-pane -t "$PILOT_WINDOW" -p -S -10 2>/dev/null || echo "")
    # IDLE prompt 検出: 過去形 + for N + > prompt
    if echo "$pane_content" | grep -qE '(Saturated|Worked|Sautéed|Baked) for [0-9]+[ms]'; then
      if echo "$pane_content" | grep -qE '^\s*>'; then
        echo "[PILOT-IDLE-CAPTURE] Pilot が IDLE 状態です（能動 capture polling 検知）"
      fi
    fi
  fi
  sleep 30
done
```

**参照**: `refs/pitfalls-catalog.md §15`（Wave U Incident 3 詳細）

---

## state stagnate 検知（observe-once 実行後）

stagnate 検知 + `>>> 実装完了:` シグナル → `plugins/twl/refs/intervention-catalog.md` の pattern-7 照合 → Layer 0 Auto 介入。
stagnate のみで完了シグナルなし → pattern-4（Layer 1 Confirm）。
