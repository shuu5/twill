## MODIFIED Requirements

### Requirement: autopilot.md の不変条件定義をリンク参照に統一

`plugins/twl/architecture/domain/contexts/autopilot.md` の不変条件 A-M の定義本文を削除し、`ref-invariants.md` へのリンクに置換しなければならない（SHALL）。定義の逐語コピー（内容変更なし）を確認してから削除すること。

#### Scenario: autopilot.md から不変条件テーブルが削除される
- **WHEN** `plugins/twl/architecture/domain/contexts/autopilot.md` を確認する
- **THEN** 不変条件 A-M の定義テーブル行は削除され、`ref-invariants.md` へのリンクが残っている

#### Scenario: autopilot.md の不変条件への言及がリンクに変換される
- **WHEN** `autopilot.md` で `不変条件` というキーワードを検索する
- **THEN** 定義テーブルではなくリンク参照として不変条件が言及されている

### Requirement: CLAUDE.md の不変条件 B 言及をリンク参照に更新

`plugins/twl/CLAUDE.md` の不変条件 B に関する言及を `ref-invariants.md` へのリンクに更新しなければならない（SHALL）。

#### Scenario: CLAUDE.md の不変条件 B がリンク参照になる
- **WHEN** `plugins/twl/CLAUDE.md` を確認する
- **THEN** 不変条件 B の記述が `ref-invariants.md` へのリンクを含む

### Requirement: su-observer/SKILL.md への境界明示とリンク追加

`plugins/twl/skills/su-observer/SKILL.md` に SU-1〜SU-7 と不変条件 A-M の境界を明示し、`ref-invariants.md` へのリンク言及を追加しなければならない（SHALL）。SU-1〜SU-7 の定義は移動せず `SKILL.md` に維持すること。

#### Scenario: su-observer/SKILL.md に境界説明とリンクが追加される
- **WHEN** `plugins/twl/skills/su-observer/SKILL.md` を確認する
- **THEN** "SU-* は supervisor 固有の application-level 制約" という説明と `ref-invariants.md` へのリンクが存在する

#### Scenario: SU-1〜SU-7 の定義が SKILL.md に維持される
- **WHEN** `plugins/twl/skills/su-observer/SKILL.md` を確認する
- **THEN** SU-1〜SU-7 の定義が削除されずに残っている
