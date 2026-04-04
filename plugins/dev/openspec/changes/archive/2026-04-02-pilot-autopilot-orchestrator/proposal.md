## Why

Pilot LLM が Phase ループ・ポーリング・merge-gate・window 管理などの機械的ロジックを手動解釈・実行しており、ポーリング中断・crash-detect 誤検知・chain 遷移停止などの問題が発生している。設計哲学「LLM は判断のために使う。機械的にできることは機械に任せる」を Pilot 側にも適用し、autopilot-orchestrator.sh に移行する。

## What Changes

- `scripts/autopilot-orchestrator.sh` を新設し、Phase ループ・ポーリング・merge-gate・window 管理・サマリー集計を script 内で完結させる
- co-autopilot SKILL.md の Step 4, 5 を orchestrator 呼び出しに簡素化
- Pilot LLM の責務を「計画承認」「retrospective 分析」「cross-issue 影響分析」に限定
- chain 遷移停止検知 + 自動 nudge 機能の実装

## Capabilities

### New Capabilities

- **autopilot-orchestrator.sh**: Phase ループ・batch 分割・ポーリング・merge-gate・window 管理・サマリー集計を一括実行するスクリプト
- **chain 遷移停止検知 + 自動 nudge**: Worker の chain が停止した場合に tmux send-keys で次コマンドを送信
- **crash-detect / window kill の原子的実行**: 順序競合を解消し、crash-detect 誤検知を防止

### Modified Capabilities

- **co-autopilot SKILL.md**: Step 4（Phase 実行）を orchestrator 呼び出しに変更。orchestrator が PHASE_COMPLETE を返すたびに Pilot が retrospective/cross-issue を実行する形に簡素化

## Impact

- `scripts/autopilot-orchestrator.sh`（新設）
- `skills/co-autopilot/SKILL.md`（Step 4, 5 の簡素化）
- 依存: `scripts/autopilot-launch.sh`, `scripts/state-read.sh`, `scripts/crash-detect.sh`, `scripts/merge-gate-execute.sh`, `scripts/auto-merge.sh`（#122）
- 非 autopilot 時の手動実行パスには影響なし
