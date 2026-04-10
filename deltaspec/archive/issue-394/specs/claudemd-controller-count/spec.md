## MODIFIED Requirements

### Requirement: Controller 数の正確な記述
`plugins/twl/CLAUDE.md` の Controller セクションは、ADR-014 に準拠した正確な数（6つ）を記述しなければならない（SHALL）。

#### Scenario: CLAUDE.md Controller セクション確認
- **WHEN** `plugins/twl/CLAUDE.md` を参照する
- **THEN** 「Controller は6つ」という見出しが存在し、6行の Controller テーブルが表示される

### Requirement: co-observer の除去
`plugins/twl/CLAUDE.md` の Controller テーブルから `co-observer` 行を削除しなければならない（SHALL）。

#### Scenario: co-observer がControllerテーブルに存在しない
- **WHEN** `plugins/twl/CLAUDE.md` の Controller テーブルを参照する
- **THEN** `co-observer` 行が存在しない

### Requirement: Supervisor セクションの追加
`plugins/twl/CLAUDE.md` に Supervisor（`su-observer`）を明示するセクションを追加しなければならない（SHALL）。

#### Scenario: Supervisor セクションの存在
- **WHEN** `plugins/twl/CLAUDE.md` を参照する
- **THEN** 「Supervisor は1つ」の見出しと `su-observer` を含むテーブルが存在する
