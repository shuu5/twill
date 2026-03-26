## Name
Autopilot

## Responsibility
セッション管理、Phase 実行、計画生成、cross-issue 影響分析、パターン検出

## Key Entities
- SessionState, IssueState, Phase, AutopilotPlan, CrossIssueWarning

## Dependencies
- PR Cycle (downstream): merge-gate を呼び出してマージ判定
- Issue Management (upstream): Issue 情報を取得
- Self-Improve (downstream): パターン検出時に ECC 照合を自動追加
