## ADDED Requirements

### Scenario: failed → done 強制遷移（#231）

- **WHEN** Issue が failed 状態で手動復旧が完了している
- **AND** Pilot が `--force-done --override-reason "理由"` を指定して状態遷移する
- **THEN** issue-{N}.json の status が `done` に遷移する
- **AND** manual_override: true と override_reason がメタデータに記録される
- **AND** `--force-done` なしの場合は failed → done 遷移が拒否される
- **AND** `--override-reason` が空文字の場合も遷移が拒否される

### Scenario: rate-limit リセット上限（#232）

- **WHEN** orchestrator のポーリング中に rate-limit（429/overloaded）が検知される
- **THEN** ポーリングカウンターが 0 にリセットされる
- **AND** リセットは最大 3 回まで許可される（max_rate_limit_resets=3）
- **AND** リセット上限到達後は通常のタイムアウト処理にフォールスルーする

### Scenario: セッション自動クリーンアップ（#233）

- **WHEN** autopilot-cleanup.sh が実行される
- **THEN** stale session（24h 超、全 Issue 完了済み）が検知・削除される
- **AND** orphan worktree（session.json に対応する running Issue がない worktree）が報告される
- **AND** `--dry-run` 指定時は検知のみで削除は行わない

### Scenario: 不変条件 K — Pilot 実装禁止（#228）

- **WHEN** Pilot セッションが実装作業（ファイル編集・コミット・PR 作成）を試みる
- **THEN** 不変条件 K により禁止される
- **AND** Worker 失敗時は根本原因分析→Issue 化を行う
- **AND** Emergency Bypass 条件を満たす場合のみ例外が許可される

## MODIFIED Requirements

### Scenario: orchestrator タイムアウト延長（#232）

- **WHEN** orchestrator がポーリングタイムアウトに達する
- **THEN** MAX_POLL のデフォルトは 720（120分相当、POLL_INTERVAL=10s）である
- **AND** `DEV_AUTOPILOT_MAX_POLL` 環境変数で上書き可能
