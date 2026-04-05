## MODIFIED Requirements

### Requirement: c-2d session-management spec のプロンプト修正

`openspec/changes/c-2d-autopilot-controller-autopilot/specs/session-management/spec.md` の autopilot-launch コマンド要件で、Worker 起動プロンプトの記述を修正しなければならない（MUST）。

旧: `Worker 起動プロンプトは /twl:workflow-setup --auto --auto-merge #${ISSUE} を使用しなければならない`
新: `Worker 起動プロンプトは /twl:workflow-setup #${ISSUE} を使用しなければならない`

#### Scenario: openspec c-2d の矛盾解消
- **WHEN** `openspec/changes/c-2d-autopilot-controller-autopilot/specs/session-management/spec.md` を確認する
- **THEN** autopilot-launch コマンド要件のプロンプト記述が `/twl:workflow-setup #${ISSUE}` のみであり、`--auto --auto-merge` が含まれない
