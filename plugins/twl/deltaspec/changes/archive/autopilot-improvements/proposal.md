## Why

Autopilot セッション 08d67b16 で判明した autopilot 基盤の 4 件の改善を実施。
state machine の遷移不足、orchestrator のタイムアウト不足、セッションクリーンアップ欠如、Pilot 実装禁止ルールの未明文化を解消する。

## What Changes

- #231: state machine に failed → done 遷移を追加（--force-done + --override-reason ガード付き）
- #232: orchestrator ポーリングタイムアウトを 60分→120分に延長、rate-limit 検知時のリセット上限追加
- #233: autopilot-cleanup.sh によるセッション自動クリーンアップ機構の追加
- #228: 不変条件 K（Pilot 実装禁止）をドキュメントと hooks で明文化

## Capabilities

### New Capabilities

- failed → done 遷移（--force-done ガード付き）
- autopilot-cleanup.sh（stale session / orphan worktree 検知・削除）
- 不変条件 K（Pilot 実装禁止）

### Modified Capabilities

- orchestrator ポーリングタイムアウト（MAX_POLL 360→720）
- rate-limit リセットに上限追加（max_rate_limit_resets=3）

## Impact

- cli/twl/src/twl/autopilot/state.py
- plugins/twl/scripts/autopilot-orchestrator.sh
- plugins/twl/scripts/autopilot-cleanup.sh（新規）
- plugins/twl/architecture/domain/contexts/autopilot.md
- plugins/twl/skills/co-autopilot/SKILL.md
