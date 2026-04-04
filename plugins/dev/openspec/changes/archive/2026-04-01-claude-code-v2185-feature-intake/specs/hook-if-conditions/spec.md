## MODIFIED Requirements

### Requirement: hook if 条件フィルタリング追加

`hooks/hooks.json` の hook エントリに `"if"` 条件フィールドを追加し、不要な発火を抑止しなければならない（SHALL）。既存の 2 hook は汎用用途のため `if` 条件なしを維持し、新規 hook パターンとして `if` 条件付きの例を追加する。

#### Scenario: 既存 PostToolUse hook の維持
- **WHEN** Edit または Write ツールが実行される
- **THEN** post-tool-use-validate.sh が発火する（if 条件なし、全ファイル対象）

#### Scenario: 既存 PostToolUseFailure hook の維持
- **WHEN** Bash ツールが失敗する
- **THEN** post-tool-use-bash-error.sh が発火する（if 条件なし、全失敗対象）

#### Scenario: if 条件付き hook の構文検証
- **WHEN** hooks/hooks.json に `"if"` フィールドを持つ hook エントリが存在する
- **THEN** Claude Code v2.1.85+ の if 条件構文に準拠していなければならない（MUST）
