## Why

`loom deep-validate` が 11 件の Warning を出力する。tools-mismatch 10 件（6 コマンドの MCP ツール frontmatter 宣言漏れ）と controller-bloat 1 件（co-issue SKILL.md が 120 行上限超過）。Warning 0 件がプロジェクトの品質基準。

## What Changes

- 6 コマンドの frontmatter に `tools` フィールドを追加し、使用する MCP ツールを宣言
- co-issue SKILL.md を 120 行以下にリファクタリング

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- **plugin-research**: frontmatter に `tools: [mcp__doobidoo__memory_search]` を宣言
- **ui-capture**: frontmatter に `tools: [mcp__playwright__browser_snapshot, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_navigate]` を宣言
- **pr-cycle-analysis**: frontmatter に `tools: [mcp__doobidoo__memory_search]` を宣言
- **autopilot-retrospective**: frontmatter に `tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search]` を宣言
- **autopilot-patterns**: frontmatter に `tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search]` を宣言
- **autopilot-summary**: frontmatter に `tools: [mcp__doobidoo__memory_store]` を宣言
- **co-issue SKILL.md**: Phase 説明の簡潔化・禁止事項のインライン化で 120 行以下に削減

## Impact

- 対象ファイル: `commands/plugin-research.md`, `commands/ui-capture.md`, `commands/pr-cycle-analysis.md`, `commands/autopilot-retrospective.md`, `commands/autopilot-patterns.md`, `commands/autopilot-summary.md`, `skills/co-issue/SKILL.md`
- 機能的変更なし（frontmatter メタデータ追加とドキュメント簡潔化のみ）
- deps.yaml への影響なし
