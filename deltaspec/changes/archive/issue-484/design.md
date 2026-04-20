## Context

co-issue SKILL.md は Phase 1〜4 のフローを定義しているが、禁止事項セクションに「Phase 3 (workflow-issue-refine) スキップ禁止」の明示がなかった。LLM は呼び出し側プロンプトを上位指示として解釈するため、「label は draft を使え」等の指示が Phase 3 呼び出しを省略するトリガーになり得る。

## Goals / Non-Goals

**Goals:**
- `plugins/twl/skills/co-issue/SKILL.md` の禁止事項セクションに MUST NOT 行を 1 行追記する
- Phase 3 が呼び出し側のラベル指示・フロー指示によってスキップされることを明示的に禁止する

**Non-Goals:**
- プロンプト受理ロジックへの検出・拒否機能追加（別 Issue 候補）
- co-architect / co-project / co-self-improve への変更（co-issue を spawn しないため不要）
- workflow-issue-refine SKILL.md の変更（既存の「quick 候補もスキップ禁止」ガードで十分）

## Decisions

1. **1 行追記のみ**: 最小変更で Issue 品質保証の不変条件を文書化する。実装複雑度ゼロ。
2. **禁止事項セクション末尾に追加**: 既存の MUST NOT 群と一貫した形式で追記。
3. **括弧内に具体例を列挙**: 「label 指示・draft 指示・gh issue create 直接指示等」と例示することで LLM の誤解釈余地を削減する。

## Risks / Trade-offs

- **リスク**: MUST NOT 文書化だけでは LLM が再度誤解釈する可能性が残る。ただし、明示的な禁止事項があることで prompt injection 的な指示に対する耐性が向上する。
- **トレードオフ**: プロンプト検証ロジックの実装は別 Issue で設計議論するため、本 Issue では文書化に留める。
