## MODIFIED Requirements

### Requirement: co-self-improve SKILL.md 参照更新

`co-self-improve/SKILL.md` 内の全 `co-observer` 参照を `su-observer` に更新しなければならない（SHALL）。frontmatter `spawnable_by`、本文、DEPRECATED セクションを含む全9箇所が対象である。

#### Scenario: SKILL.md 参照が su-observer に更新されている
- **WHEN** `plugins/twl/skills/co-self-improve/SKILL.md` を参照したとき
- **THEN** `co-observer` という文字列が1つも存在せず、全て `su-observer` に置き換わっている

#### Scenario: frontmatter の spawnable_by が更新されている
- **WHEN** `plugins/twl/skills/co-self-improve/SKILL.md` の frontmatter を確認したとき
- **THEN** `spawnable_by: [su-observer]` と記載されている

#### Scenario: DEPRECATED セクションが正しく更新されている
- **WHEN** DEPRECATED セクションを確認したとき
- **THEN** 「su-observer の supervise モードに移管」と記述されている

### Requirement: deps.yaml spawnable_by 更新

`deps.yaml` の `co-self-improve` エントリの `spawnable_by` フィールドを `su-observer` に更新しなければならない（SHALL）。

#### Scenario: deps.yaml が su-observer を参照している
- **WHEN** `deps.yaml` の `co-self-improve` エントリを確認したとき
- **THEN** `spawnable_by` が `[su-observer]` を含み、`co-observer` を含まない
