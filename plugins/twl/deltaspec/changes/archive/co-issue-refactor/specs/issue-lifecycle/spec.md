## MODIFIED Requirements

### Scenario: Phase 4 一括作成（#204 リファクタ）

- **WHEN** 精緻化が完了し全候補が提示される
- **THEN** co-issue は `/twl:workflow-issue-create` を呼び出して Phase 4 を委譲する
- **AND** workflow-issue-create が refined ラベル作成 → ユーザー確認 → routing（単一/一括/クロスリポ）→ Board 同期 → クリーンアップ → 通知 の 6 Step を実行する
- **AND** co-issue SKILL.md 内に Phase 4 の実装ロジックは含まれない

### Scenario: co-issue thin orchestrator 化（#205）

- **WHEN** co-issue が実行される
- **THEN** co-issue SKILL.md は Phase ディスパッチのみを行う thin orchestrator として動作する
- **AND** Phase 1-3 は `/twl:workflow-issue-refine` に委譲される
- **AND** Phase 4 は `/twl:workflow-issue-create` に委譲される
- **AND** co-issue の calls から ref-issue-template-bug, ref-issue-template-feature, ref-project-model, ref-issue-quality-criteria, ref-glossary-criteria への直接参照が除去される
- **AND** これらの reference は各 workflow が内部で参照する
