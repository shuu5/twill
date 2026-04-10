## Why

`co-self-improve` SKILL.md が旧コンポーネント名 `co-observer` を参照しており、ADR-014 による supervisor 再設計で名称が `su-observer` に変更された後も更新されていない。参照不整合を解消し、ドキュメントとシステム実態を一致させる必要がある。

## What Changes

- `plugins/twl/skills/co-self-improve/SKILL.md`: 全 `co-observer` 参照 (L5, L7, L13, L20, L27, L28, L41, L47, L49) を `su-observer` に更新
  - frontmatter の `spawnable_by: [co-observer]` → `spawnable_by: [su-observer]`
  - 本文内のコンポーネント名参照を全て更新
  - DEPRECATED セクションの「co-observer の supervise モード」→「su-observer の supervise モード」
- `deps.yaml`: `co-self-improve` エントリの `spawnable_by` を `su-observer` に更新

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `co-self-improve` スキルが正しい supervisor コンポーネント (`su-observer`) から spawn されることを示す frontmatter を持つ
- ドキュメント内のコンポーネント参照が現行アーキテクチャと一致する

## Impact

- `plugins/twl/skills/co-self-improve/SKILL.md`: テキスト更新のみ（機能変更なし）
- `deps.yaml`: `spawnable_by` フィールド更新のみ
- 依存コンポーネント: なし（参照更新のみ、動作変更なし）
