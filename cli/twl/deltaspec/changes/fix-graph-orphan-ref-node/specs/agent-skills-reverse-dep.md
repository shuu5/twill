## MODIFIED Requirements

### Requirement: agent.skills の reverse dependency 反映

`build_graph()` は agent の `skills` フィールドに列挙された skill を、当該 skill ノードの `required_by` に追加しなければならない（SHALL）。

#### Scenario: agent が skills フィールドで reference skill を参照
- **WHEN** deps.yaml の agent エントリに `skills: [ref-skill-a]` が定義されている
- **THEN** `skill:ref-skill-a` ノードの `required_by` に `('agent', agent_name)` が含まれる

#### Scenario: agent.skills の参照先がグラフに存在しない
- **WHEN** agent の skills に列挙された skill がグラフに存在しない
- **THEN** その skill は無視され、エラーは発生しない

#### Scenario: agent.skills で参照される skill が orphan にならない
- **WHEN** agent が skills フィールドで skill を参照している
- **THEN** `find_orphans()` の unused リストにその skill が含まれない
