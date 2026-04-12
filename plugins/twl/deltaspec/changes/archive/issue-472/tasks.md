## 1. orchestrator.py: Stagnation 検知追加

- [x] 1.1 `STAGNATION_THRESHOLD` 定数を追加（デフォルト: 900、環境変数 `DEV_AUTOPILOT_STAGNATION_THRESHOLD` でオーバーライド）
- [x] 1.2 `_check_stagnation(issue, repo_id)` メソッドを実装（`updated_at` 読み取り → 経過時間比較）
- [x] 1.3 `_poll_single` の running ブランチに stagnation チェックを追加（nudge → カウント超過で failed）
- [x] 1.4 `_poll_phase` の running ブランチに stagnation チェックを追加（同上）
- [x] 1.5 stagnation_nudge_count の per-issue カウント管理を追加（dict で管理）

## 2. co-autopilot SKILL.md: ScheduleWakeup ベース polling

- [x] 2.1 Step 4 の bash while ループを削除し、ScheduleWakeup(300) + 能動確認指示に書き換え
- [x] 2.2 wake-up 時の確認手順を記述: PHASE_COMPLETE grep → Worker updated_at チェック → stagnation 判定
- [x] 2.3 MAX_WAIT_MINUTES（30 分）超過後の状況精査モードの指示を追加
- [x] 2.4 状況精査モードの判断フロー（全 terminal → Phase 完了、stall → 回復試行 → 失敗確定）を記述

## 3. テスト

- [x] 3.1 `orchestrator.py` の `_check_stagnation` ユニットテストを作成（stagnation あり/なし/updated_at 欠如の3ケース）
- [x] 3.2 `_poll_single` の stagnation → nudge → failed フローの統合テストを追加
- [x] 3.3 `STAGNATION_THRESHOLD` 環境変数オーバーライドのテストを追加
