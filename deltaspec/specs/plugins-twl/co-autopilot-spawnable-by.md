## Requirements

### Requirement: co-autopilot spawnable_by deps.yaml 整合

`plugins/twl/deps.yaml` の co-autopilot エントリの `spawnable_by` フィールドは `[user, su-observer]` でなければならない（SHALL）。

#### Scenario: deps.yaml と SKILL.md の spawnable_by 一致
- **WHEN** `plugins/twl/deps.yaml` の co-autopilot エントリを参照する
- **THEN** `spawnable_by` が `[user, su-observer]` であり、`plugins/twl/skills/co-autopilot/SKILL.md` frontmatter の `spawnable_by: [user, su-observer]` と一致する

#### Scenario: twl check PASS
- **WHEN** `twl check` を実行する
- **THEN** co-autopilot の spawnable_by に関する整合性エラーが報告されずに PASS する
