## MODIFIED Requirements

### Requirement: コマンド frontmatter tools 宣言

6 コマンドファイルの先頭に YAML frontmatter を追加し、body 内で参照する MCP ツールを `tools` フィールドに宣言しなければならない（SHALL）。

対象と宣言内容:
- `commands/plugin-research.md` → `tools: [mcp__doobidoo__memory_search]`
- `commands/ui-capture.md` → `tools: [mcp__playwright__browser_snapshot, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_navigate]`
- `commands/pr-cycle-analysis.md` → `tools: [mcp__doobidoo__memory_search]`
- `commands/autopilot-retrospective.md` → `tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search]`
- `commands/autopilot-patterns.md` → `tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search]`
- `commands/autopilot-summary.md` → `tools: [mcp__doobidoo__memory_store]`

#### Scenario: frontmatter 追加後の deep-validate
- **WHEN** 6 コマンドに frontmatter `tools` フィールドを追加した状態で `loom deep-validate` を実行する
- **THEN** tools-mismatch 警告が 0 件になる

#### Scenario: frontmatter 形式の正確性
- **WHEN** 追加した frontmatter を解析する
- **THEN** `---` で囲まれた YAML ブロックの `tools` フィールドにインライン配列形式で MCP ツール名が宣言されている

### Requirement: co-issue SKILL.md controller-bloat 解消

co-issue SKILL.md を 120 行以下にリファクタリングしなければならない（MUST）。ロジックの変更は行わず、説明文の簡潔化のみで行数を削減する。

#### Scenario: 行数削減後の deep-validate
- **WHEN** co-issue SKILL.md を 120 行以下に削減した状態で `loom deep-validate` を実行する
- **THEN** controller-bloat 警告が 0 件になる

#### Scenario: 機能保持の確認
- **WHEN** リファクタリング後の co-issue SKILL.md の内容を確認する
- **THEN** 全 Phase（探索→分解→精緻化→作成）の指示と禁止事項が保持されている
