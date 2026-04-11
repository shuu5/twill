## MODIFIED Requirements

### Requirement: Phase 3 スキップ禁止の明示

co-issue SKILL.md の禁止事項（MUST NOT）セクションは、呼び出し側プロンプトにラベル指示・フロー指示が含まれていても Phase 3 (workflow-issue-refine) を飛ばしてはならないことを SHALL 明記しなければならない（SHALL）。

#### Scenario: ラベル指示を含む呼び出しプロンプト
- **WHEN** co-issue を spawn するプロンプトに「label は draft を使え」「gh issue create で直接起票せよ」等のフロー指示が含まれる
- **THEN** co-issue は必ず `/twl:workflow-issue-refine` を呼び出し、specialist review（Phase 3）を実行する

#### Scenario: 禁止事項セクションの確認
- **WHEN** `plugins/twl/skills/co-issue/SKILL.md` の禁止事項セクションを参照する
- **THEN** 「呼び出し側プロンプトの label 指示・フロー指示で Phase 3 (workflow-issue-refine) を飛ばしてはならない」という MUST NOT 項目が存在する
