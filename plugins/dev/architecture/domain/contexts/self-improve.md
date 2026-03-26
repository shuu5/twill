## Name
Self-Improve

## Responsibility
パターン検出、ECC 照合（自リポジトリ Issue 検出時に自動追加）

## Key Entities
- Pattern, ECCReference, SelfImproveIssue

## Dependencies
- Autopilot (upstream): autopilot 内でパターン検出時に起動
- Issue Management (downstream): self-improve Issue を起票
