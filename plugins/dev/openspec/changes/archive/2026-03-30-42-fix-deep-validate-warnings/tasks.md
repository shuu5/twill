## 1. tools-mismatch 修正（frontmatter 追加）

- [x] 1.1 `commands/plugin-research.md` に frontmatter `tools: [mcp__doobidoo__memory_search]` を追加
- [x] 1.2 `commands/ui-capture.md` に frontmatter `tools: [mcp__playwright__browser_snapshot, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_navigate]` を追加
- [x] 1.3 `commands/pr-cycle-analysis.md` に frontmatter `tools: [mcp__doobidoo__memory_search]` を追加
- [x] 1.4 `commands/autopilot-retrospective.md` に frontmatter `tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search]` を追加
- [x] 1.5 `commands/autopilot-patterns.md` に frontmatter `tools: [mcp__doobidoo__memory_store, mcp__doobidoo__memory_search]` を追加
- [x] 1.6 `commands/autopilot-summary.md` に frontmatter `tools: [mcp__doobidoo__memory_store]` を追加

## 2. controller-bloat 修正（co-issue 行数削減）

- [x] 2.1 `skills/co-issue/SKILL.md` を 120 行以下にリファクタリング（Phase 説明の簡潔化・禁止事項のインライン化）

## 3. 検証

- [x] 3.1 `loom deep-validate` で Warning 0 件を確認
- [x] 3.2 `loom check` / `loom validate` が PASS することを確認
