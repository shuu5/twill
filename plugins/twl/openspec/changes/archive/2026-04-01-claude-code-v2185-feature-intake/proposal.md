## Why

Claude Code v2.1.72〜v2.1.88 で hook `if` 条件フィルタリング、エージェント frontmatter 拡張（effort / skills / isolation）、`${CLAUDE_PLUGIN_DATA}` 永続ディレクトリ、`Agent(agent_type)` スポーン制限が追加された。現在の dev plugin はこれらを活用しておらず、hook の不要発火、Controller の effort 未宣言、specialist への ref-* スキル未注入といった非効率が残っている。

## What Changes

- `hooks/hooks.json` の全 hook に `"if"` 条件を追加し、不要な発火を抑止
- Controller（skills/ 配下 SKILL.md）に `effort` フィールドを追加
- specialist エージェントに `skills` フィールドで ref-* スキルを事前注入
- `isolation: "worktree"` を co-autopilot Worker に適用検討
- `${CLAUDE_PLUGIN_DATA}` を永続状態ディレクトリとして活用検討
- Controller の `tools` フィールドに `Agent(agent_type)` スポーン制限を宣言
- deps.yaml を新フィールドに対応して更新

## Capabilities

### New Capabilities

- hook `if` 条件による選択的発火（PostToolUse の Edit|Write で deps.yaml 変更時のみバリデーション実行など）
- Controller effort 宣言による Claude Code のリソース最適化
- specialist への ref-* スキル事前注入で Skill tool 経由のリファレンス参照が可能に
- Agent(agent_type) スポーン制限による Controller のスポーン範囲明示

### Modified Capabilities

- hooks/hooks.json: 既存 2 hook に `if` 条件追加
- skills/*/SKILL.md: 全 9 スキルに effort フィールド追加
- agents/*.md: specialist に skills フィールド追加
- deps.yaml: 新 frontmatter フィールド（effort, skills, isolation, tools）を反映

## Impact

- **hooks/hooks.json**: 2 hook エントリの修正（`if` フィールド追加）
- **skills/*/SKILL.md**: 9 ファイルの frontmatter 修正（effort 追加）
- **agents/*.md**: 最大 28 ファイルの frontmatter 修正（skills 追加）
- **deps.yaml**: コンポーネント定義への新フィールド反映
- **loom CLI**: `loom check` / `loom validate` で新フィールドの検証が PASS すること
- **前提**: Claude Code v2.1.85+（現環境 v2.1.87 で確認済み）
