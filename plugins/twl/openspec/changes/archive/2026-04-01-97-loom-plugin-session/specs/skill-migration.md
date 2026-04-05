## ADDED Requirements

### Requirement: spawn SKILL.md 移植

spawn スキル（113 行）を plugin の `skills/spawn/SKILL.md` に移植し、パス参照を plugin-relative に更新しなければならない（SHALL）。

#### Scenario: SKILL.md のパス参照
- **WHEN** `skills/spawn/SKILL.md` 内のスクリプト呼び出しを確認する
- **THEN** `$PLUGIN_DIR/scripts/` パターンで plugin 内スクリプトを参照している

#### Scenario: 機能保持
- **WHEN** spawn スキルの内容を確認する
- **THEN** 新規 Claude Code セッションを tmux window で起動する機能が記載されている

### Requirement: observe SKILL.md 移植

observe スキル（67 行）を plugin の `skills/observe/SKILL.md` に移植し、パス参照を plugin-relative に更新しなければならない（SHALL）。

#### Scenario: SKILL.md のパス参照
- **WHEN** `skills/observe/SKILL.md` 内のスクリプト呼び出しを確認する
- **THEN** `$PLUGIN_DIR/scripts/` パターンで plugin 内スクリプトを参照している

### Requirement: fork SKILL.md 移植

fork スキル（76 行）を plugin の `skills/fork/SKILL.md` に移植し、パス参照を plugin-relative に更新しなければならない（SHALL）。

#### Scenario: SKILL.md のパス参照
- **WHEN** `skills/fork/SKILL.md` 内のスクリプト呼び出しを確認する
- **THEN** `$PLUGIN_DIR/scripts/` パターンで plugin 内スクリプトを参照している
