## ADDED Requirements

### Requirement: su-observer ディレクトリ作成
`plugins/twl/skills/su-observer/` ディレクトリが存在しなければならない（SHALL）。
`plugins/twl/skills/co-observer/` は削除されていなければならない（MUST）。

#### Scenario: ディレクトリリネーム完了
- **WHEN** `plugins/twl/skills/` ディレクトリを確認する
- **THEN** `co-observer/` が存在せず、`su-observer/` が存在する

### Requirement: su-observer SKILL.md の frontmatter
`su-observer/SKILL.md` は `type: supervisor` で作成されなければならない（MUST）。
`spawnable_by: [user]` を持たなければならない（SHALL）。

#### Scenario: supervisor 型 frontmatter
- **WHEN** `su-observer/SKILL.md` の frontmatter を参照する
- **THEN** `type: supervisor`、`name: twl:su-observer`、`spawnable_by: [user]` が定義されている

### Requirement: Step 0〜7 の基本構造定義
`su-observer/SKILL.md` は ADR-014 Decision 2 に基づく Step 0〜7 の構造を持たなければならない（MUST）。

#### Scenario: Step 0〜7 の全ステップ存在
- **WHEN** `su-observer/SKILL.md` の見出し構造を確認する
- **THEN** Step 0 から Step 7 まで全てのステップが定義されている

#### Scenario: Step 4〜7 はプレースホルダー
- **WHEN** Step 4〜7 の内容を参照する
- **THEN** 後続 Issue で詳細化される旨のプレースホルダーが記載されている

## MODIFIED Requirements

### Requirement: deps.yaml の co-observer 参照更新
`plugins/twl/deps.yaml` の `co-observer` 参照が `su-observer` に更新されなければならない（MUST）。

#### Scenario: deps.yaml 参照更新
- **WHEN** `plugins/twl/deps.yaml` を参照する
- **THEN** `co-observer` キーが存在せず、`su-observer` キーが `type: supervisor` で定義されている

## REMOVED Requirements

### Requirement: co-observer SKILL.md の削除
`plugins/twl/skills/co-observer/SKILL.md` は削除されていなければならない（MUST）。

#### Scenario: co-observer 削除確認
- **WHEN** `plugins/twl/skills/co-observer/` の存在を確認する
- **THEN** ディレクトリが存在しない

## RENAMED Requirements

### Requirement: twl validate の PASS
`twl validate` が PASS しなければならない（MUST）。

#### Scenario: validate 通過
- **WHEN** `twl validate` を実行する
- **THEN** エラーなしで PASS する（supervisor 型が types.yaml に定義済みであることが前提）
