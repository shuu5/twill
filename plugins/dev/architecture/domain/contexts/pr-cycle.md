## Name
PR Cycle

## Responsibility
レビュー、テスト、マージ。verify → 並列レビュー → test → fix → report のチェーン

## Key Entities
- PullRequest, ReviewResult, Finding, MergeGateDecision, SpecialistOutput

## Dependencies
- Autopilot (upstream): autopilot から merge-gate として呼び出される
- Issue Management (upstream): AC 抽出、スコープ判定で Issue 情報を参照
