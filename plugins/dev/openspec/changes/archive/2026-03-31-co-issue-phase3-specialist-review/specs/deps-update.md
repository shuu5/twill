## MODIFIED Requirements

### Requirement: deps.yaml に新コンポーネントを登録

deps.yaml に以下の変更を適用しなければならない（SHALL）:

**追加:**
- `issue-critic`: type: specialist, model: sonnet, path: agents/issue-critic.md
- `issue-feasibility`: type: specialist, model: sonnet, path: agents/issue-feasibility.md
- `ref-issue-quality-criteria`: type: reference, path: refs/ref-issue-quality-criteria.md

**co-issue の calls 更新:**
- `issue-dig` を削除
- `issue-assess` を削除
- `specialist: issue-critic` を追加
- `specialist: issue-feasibility` を追加
- `reference: ref-issue-quality-criteria` を追加
- `can_spawn` に `specialist` を追加

**削除:**
- `issue-dig` エントリ
- `issue-assess` エントリ

#### Scenario: loom check が PASS
- **WHEN** deps.yaml 更新後に `loom check` を実行する
- **THEN** エラーなしで PASS する

#### Scenario: loom validate が PASS
- **WHEN** deps.yaml 更新後に `loom validate` を実行する
- **THEN** 双方向整合性検証がエラーなしで PASS する
