## ADDED Requirements

### Requirement: deps.yaml v3 の作成

deps.yaml v3.0 フォーマットで全コンポーネント（scripts 7 件 + skills 3 件）を登録しなければならない（SHALL）。

#### Scenario: バージョンと plugin 名
- **WHEN** deps.yaml を読む
- **THEN** `version: "3.0"` かつ `plugin: session` が設定されている

#### Scenario: entry_points の定義
- **WHEN** deps.yaml の entry_points を確認する
- **THEN** spawn, observe, fork の 3 スキルが登録されている

#### Scenario: 全コンポーネント登録
- **WHEN** deps.yaml の skills セクションと scripts セクションを確認する
- **THEN** skills 3 件と scripts 7 件が登録されている

#### Scenario: 依存関係の正確性
- **WHEN** session-comm の calls を確認する
- **THEN** session-state への依存が宣言されている

### Requirement: loom check PASS

`loom check` を実行した結果、Missing が 0 でなければならない（MUST）。

#### Scenario: loom check 実行
- **WHEN** plugin ルートで `loom check` を実行する
- **THEN** Missing 0 で PASS が返る

### Requirement: loom validate PASS

`loom validate` を実行した結果、Violations が 0 でなければならない（MUST）。

#### Scenario: loom validate 実行
- **WHEN** plugin ルートで `loom validate` を実行する
- **THEN** Violations 0 で PASS が返る
