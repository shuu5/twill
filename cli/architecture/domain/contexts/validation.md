## Name
Validation

## Responsibility
check / validate / deep-validate / audit の4段階検証。構造の正しさを機械的に保証

## Key Entities
- Violation, CheckResult, AuditSection, AuditReport

## Dependencies
- Plugin Structure (upstream): コンポーネントグラフを入力として受け取る
- Type System (upstream): 型ルールを参照して違反を検出
- Chain Management (upstream): chain 整合性検証を統合
