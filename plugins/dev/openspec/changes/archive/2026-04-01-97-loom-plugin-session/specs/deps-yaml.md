## ADDED Requirements

### Requirement: deps.yaml v3 構築

deps.yaml v3 フォーマットで全コンポーネント（scripts 7 件 + skills 3 件）を登録しなければならない（SHALL）。

#### Scenario: scripts 登録
- **WHEN** deps.yaml の scripts セクションを確認する
- **THEN** session-state.sh, session-comm.sh, cld, cld-spawn, cld-observe, cld-fork の 6 件が `type: script` で登録されている

#### Scenario: skills 登録
- **WHEN** deps.yaml の skills セクションを確認する
- **THEN** spawn, observe, fork の 3 件が `type: skill` で登録されている

### Requirement: loom check PASS

`loom check` を実行して Missing 0 で PASS しなければならない（MUST）。

#### Scenario: loom check 実行
- **WHEN** plugin ルートで `loom check` を実行する
- **THEN** 全コンポーネントが検出され、Missing 0 / Extra 0 で PASS する

### Requirement: loom validate PASS

`loom validate` を実行して Violations 0 で PASS しなければならない（MUST）。

#### Scenario: loom validate 実行
- **WHEN** plugin ルートで `loom validate` を実行する
- **THEN** deps.yaml のスキーマ検証が通り、Violations 0 で PASS する
