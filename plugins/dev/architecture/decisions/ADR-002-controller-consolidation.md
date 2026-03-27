# ADR-002: Controller Consolidation (9 -> 4)

## Status
Accepted

## Context

旧プラグイン (claude-plugin-dev) では 9 controllers が存在し、以下の問題を引き起こしていた:

- 責務の分散と重複（self-improve と co-autopilot の境界が曖昧）
- Controller 間の暗黙的な依存関係
- SKILL.md の肥大化（複数 controller が類似した指示を持つ）
- 新規 controller 追加時の既存 controller との衝突リスク

旧 9 controllers:
co-autopilot, co-issue, co-project, co-architect, self-improve, plugin, issue-refactor, project-migrate, project-snapshot

## Decision

4つの co-* controllers に統合する。Implementation / Non-implementation の2カテゴリに分類する。

| Controller | 役割 | カテゴリ |
|------------|------|----------|
| co-autopilot | Issue 実装の実行（単一 Issue も autopilot 経由） | Implementation |
| co-issue | Issue 作成（要望→Issue 変換） | Non-implementation |
| co-project | プロジェクト管理（create / migrate / snapshot） | Non-implementation |
| co-architect | アーキテクチャ設計 | Non-implementation |

### 旧 controller の吸収先

| 旧 Controller | 吸収先 | 根拠 |
|----------------|--------|------|
| self-improve | co-autopilot | 自リポジトリ Issue 検出時に ECC 照合を workflow 内で自動追加。別概念にしない |
| plugin | co-project | テンプレート（"plugin"）として吸収。保守は通常ワークフロー + loom CLI |
| issue-refactor | merge-gate | 自動 Issue 起票で代替。手動なら loom audit → co-issue |
| project-migrate | co-project | 引数 `migrate` として統合 |
| project-snapshot | co-project | 引数 `snapshot` として統合 |

## Consequences

### Positive
- 責務の明確化（各 controller が独立した領域を担当）
- テスト対象の削減（9 → 4 SKILL.md）
- 新規開発者の学習コスト低減

### Negative
- 各 controller の責務増大（特に co-project は create/migrate/snapshot を担う）
- SKILL.md の肥大化リスク

### Mitigations
- bloat 基準（200行以下）の遵守を loom audit で検証
- 責務増大時は workflow への委譲で SKILL.md を薄く保つ
