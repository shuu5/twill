## Why

旧 dev plugin (claude-plugin-dev) の 9 controllers は責務の分散・重複・暗黙的依存により保守性が低下していた。ADR-002 に基づき 4 co-* controllers に統合することで責務を明確化し、autopilot-first アーキテクチャの中核を構築する。

## What Changes

- 4 controllers（co-autopilot, co-issue, co-project, co-architect）の SKILL.md を新規作成
- co-autopilot: 旧 controller-autopilot + controller-self-improve の機能を統合
- co-issue: 旧 controller-issue の 4 Phase フローを移植 + controller-issue-refactor の機能を merge-gate 自動 Issue 起票に代替
- co-project: 旧 controller-project + controller-project-migrate + controller-project-snapshot + controller-plugin を create/migrate/snapshot 3モードに統合
- co-architect: 旧 controller-architect の対話的設計フローを移植
- co-issue 用 Issue テンプレート（bug.md, feature.md）を移植
- deps.yaml の skills セクションを更新（can_spawn 等の詳細定義）

## Capabilities

### New Capabilities

- co-autopilot に self-improve Issue 検出時の ECC 照合自動追加ロジック
- co-project の create/migrate/snapshot 3モードルーティング（Step 0 分岐）
- 全長時間ワークフロー（co-autopilot, co-issue, co-architect）で TaskCreate/TaskList による進捗管理

### Modified Capabilities

- co-issue に explore-summary 検出フローを統合（B-7 で追加済みの stub を実装）
- co-architect に --group モード対応（architect-group-refine 呼び出し）
- deps.yaml の controller 定義を can_spawn 詳細化で更新

## Impact

- 変更対象: skills/co-*/SKILL.md（4ファイル）, deps.yaml, Issue テンプレート
- 依存: architecture/domain/contexts/ の設計定義に準拠
- 旧 plugin の 9 controllers は参照のみ（本リポジトリでは削除対象なし）
- loom validate のパスが必須
