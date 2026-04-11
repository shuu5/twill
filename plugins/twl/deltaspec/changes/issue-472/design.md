## Context

co-autopilot の Pilot（SKILL.md Step 4）は orchestrator を nohup で起動後、`grep PHASE_COMPLETE` の bash while ループで待機する設計になっている。しかし Bash tool には最大タイムアウトがあるため、7200 秒相当のループは実行不可能。Pilot LLM は実際には ScheduleWakeup を使って受動的に待機するが、wake-up 時に state file を能動確認する指示がなく、PHASE_COMPLETE が来なければ再スリープするだけになっている。

Worker が stall（workflow_done 未更新）した場合、orchestrator の _poll_phase/Python 側は check_and_nudge でパターンマッチ nudge を試みるが、hash 差分頼みのため同じ出力が続く stall には反応しない。orchestrator から PHASE_COMPLETE が出力されないため Pilot も気づかず、両者が完全 stall する。

## Goals / Non-Goals

**Goals:**
- Pilot が ScheduleWakeup wake-up 時に state file と orchestrator ログを能動確認する
- Worker の `updated_at` stagnation（一定時間更新なし）を Pilot および orchestrator が検知する
- PHASE_COMPLETE timeout 後に Pilot が状況精査モードに入り、適切なリカバリーアクションを実行する
- orchestrator の _poll_phase/_poll_single に updated_at stagnation 検知を追加する

**Non-Goals:**
- Worker 実行モデルの変更（Worker は引き続き tmux window + state file で動作）
- su-observer の役割を Pilot に移植すること（su-observer は依然として外部監視層）
- SKILL.md の bash while ループを完全削除すること（dev 環境での短時間テスト用に残す）

## Decisions

### D1: SKILL.md polling を ScheduleWakeup ベースに変更

現状の while ループ（MAX_POLL=720, POLL_INTERVAL=10）は Bash タイムアウトにより機能しない。Pilot は ScheduleWakeup(300s) で 5 分間隔の wake-up サイクルを採用する。

wake-up 時の確認項目:
1. `grep -c "PHASE_COMPLETE" "$_ORCH_LOG"` で完了確認
2. 未完了の場合、全 Worker の state file を読んで `updated_at` を確認
3. `updated_at` が最終確認時刻から `STAGNATION_THRESHOLD`（デフォルト: 15 分）以上古ければ stall とみなす

### D2: orchestrator.py に updated_at stagnation 検知を追加

`_poll_single` / `_poll_phase` の running ブランチで、既存の `_check_and_nudge` の前後に `_check_stagnation()` を呼び出す:

```python
def _check_stagnation(self, issue: str, entry: str, repo_id: str) -> bool:
    """updated_at が STAGNATION_THRESHOLD 以上古い場合 True を返す"""
    updated_at_str = _read_state(issue, "updated_at", self.autopilot_dir, repo_id)
    if not updated_at_str:
        return False
    try:
        updated_at = datetime.fromisoformat(updated_at_str)
        elapsed = (datetime.now() - updated_at).total_seconds()
        return elapsed >= STAGNATION_THRESHOLD
    except ValueError:
        return False
```

stagnation 検知時は `status=stalled` を書き込み、`_cleanup_worker` を呼ばずに nudge を送信して自然回復を待つ。連続 `MAX_STAGNATION_NUDGE` 回（デフォルト: 3）を超えたら `status=failed` に遷移。

`STAGNATION_THRESHOLD` は環境変数 `DEV_AUTOPILOT_STAGNATION_THRESHOLD` でオーバーライド可（デフォルト: 900 秒 = 15 分）。

### D3: SKILL.md timeout 後の状況精査モード

`MAX_POLL` timeout（デフォルト: 30 分）後、Pilot は単純再実行せず以下を順番に確認:
1. Worker 数と各 status（running/merge-ready/done/failed/stalled）を列挙
2. stalled Worker がある場合: `session-comm.sh inject-file` で詳細状況を送信
3. failed Worker がある場合: failure reason を確認して次 Phase に進むか判断
4. 全 Worker が merge-ready/done/failed のいずれかであれば: Phase 完了として進行

これにより su-observer 不在でも Pilot が自律的に Phase を完了または診断できる。

## Risks / Trade-offs

- **D1 ScheduleWakeup 遅延**: 5 分間隔のため PHASE_COMPLETE 受信が最大 5 分遅れる。許容範囲内（これまで 30-90 分 stall と比較して無視できる）
- **D2 stagnation 誤検知**: Worker が重い処理で 15 分以上 state 更新しない場合に誤 stall 判定。STAGNATION_THRESHOLD を環境変数で調整可能にすることで緩和
- **D3 状況精査モードの LLM 依存**: Pilot LLM の判断精度に依存するリカバリー。su-observer の外部監視と二重チェックになるが、su-observer 不在時のセーフティネットとして機能
- **後方互換性**: `status=stalled` は新規ステータス。既存の orchestrator が未対応の場合、`running` として継続扱いされるため破壊的変更にはならない
