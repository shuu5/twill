# supervise 1 iteration — 必須並行チャンネル

co-autopilot を supervise している間、1 iteration で以下のチャンネルを並行実行しなければならない（SHALL）:

| チャンネル | 目的 | Worker spawn あり | Pilot-only chain | 閾値/間隔 |
|---|---|---|---|---|
| Monitor tool (Pilot) | Pilot window の tail streaming | MUST | MUST + **PILOT-PHASE-COMPLETE** filter | 随時 |
| `cld-observe-any --pattern '(ap-|wt-co-).*' --interval 180` | Worker 群 + Pilot window polling | MUST | MUST（`wt-co-*` 必須） | 3 分 |
| `.supervisor/events/` イベントファイル + mtime 監視 | hook プライマリ / polling フォールバック | MUST | MUST | `AUTOPILOT_STAGNATE_SEC` デフォルト 600s |
| `heartbeat-watcher.sh` | 5 分 silence → 自動 capture-pane | SHOULD | **MUST**（Pilot-only では唯一の能動検知手段） | 5 分 |
| `session-comm.sh capture` (ad-hoc) | 実体確認 | 必要時 | 必要時 | 必要時 |
| `gh pr list` (Pilot 向け) | state.pr と実体の差分検知 | Wave 管理時 | Wave 管理時（`in:body #N` syntax 使用） | Wave 管理時 |
| `[BUDGET-LOW]` tmux status line budget 残量パース | budget 枯渇前の安全停止 | MUST | MUST | 残り 15 分 or 90% 消費 |
| `[PERMISSION-PROMPT]` cld-observe-any 検知 | Worker permission prompt stuck 検出（`refs/pitfalls-catalog.md §4.7` 起点） | MUST | MUST | 即時 |

## cld-observe-any 使用例（Monitor tool と必ず同時起動）

```bash
# pattern '(ap-|wt-co-).*' で Worker window と Pilot window の両方を対象にする（Issue #948 修正）
plugins/session/scripts/cld-observe-any \
  --pattern '(ap-|wt-co-).*' --interval 180 --stagnate-sec 600 \
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
cld-observe-loop --pattern '(ap-|wt-co-).*' --interval 180
```

Monitor tool + cld-observe-any は必ず同時起動すること（SHALL）。どちらか一方のみの使用は禁止。
heartbeat-watcher.sh は co-autopilot spawn 直後に budget-monitor-watcher.sh と同時に起動すること（MUST）。

## Hybrid 検知ポリシー

各チャネルで `.supervisor/events/` 配下のイベントファイルをプライマリとして確認し、不在時のみ polling にフォールバックする。詳細は `refs/monitor-channel-catalog.md` の「Hybrid 検知ポリシー」セクションを参照。

## state stagnate 検知（observe-once 実行後）

stagnate 検知 + `>>> 実装完了:` シグナル → `plugins/twl/refs/intervention-catalog.md` の pattern-7 照合 → Layer 0 Auto 介入。
stagnate のみで完了シグナルなし → pattern-4（Layer 1 Confirm）。
