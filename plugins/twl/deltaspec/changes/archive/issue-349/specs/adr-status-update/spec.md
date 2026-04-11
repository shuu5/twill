## MODIFIED Requirements

### Requirement: ADR-014 ステータス更新

ADR-014-supervisor-redesign.md の Status フィールドを Accepted に更新しなければならない（SHALL）。

#### Scenario: ADR-014 が Accepted に変更されている
- **WHEN** `plugins/twl/architecture/decisions/ADR-014-supervisor-redesign.md` を参照する
- **THEN** Status フィールドが `Accepted` であること

### Requirement: ADR-013 ステータス更新

ADR-013-observer-first-class.md の Status フィールドを Superseded by ADR-014 に更新しなければならない（SHALL）。

#### Scenario: ADR-013 が Superseded に変更されている
- **WHEN** `plugins/twl/architecture/decisions/ADR-013-observer-first-class.md` を参照する
- **THEN** Status フィールドが `Superseded by ADR-014` であること

### Requirement: ADR-013 Superseded 注記追加

ADR-013 の冒頭に Superseded 注記ブロックを追加しなければならない（SHALL）。

#### Scenario: ADR-013 冒頭に注記が存在する
- **WHEN** ADR-013 の先頭を参照する
- **THEN** `[SUPERSEDED]` を含む注記ブロックと ADR-014 へのリンクが存在すること
