## Name
Loom Integration

## Responsibility
loom CLI との連携。validate、audit、chain generate の呼び出しと結果消費

## Key Entities
- ValidationResult, AuditReport, ChainDefinition, DepsYaml

## Dependencies
- 全 Context (横断): 全 Context が loom CLI の検証結果を消費
