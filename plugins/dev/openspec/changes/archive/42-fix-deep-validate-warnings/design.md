## Context

`loom deep-validate` は各コンポーネントの body 内で参照される `mcp__*` ツールが frontmatter の `tools` フィールドに宣言されているか検証する。現在 6 コマンドに宣言漏れがあり 10 件の tools-mismatch 警告が発生。また co-issue SKILL.md が 135 行で 120 行上限を超過し controller-bloat 警告が 1 件発生。

frontmatter 形式は `---` で囲んだ YAML ブロックで、`tools: [tool1, tool2]` の配列形式。コマンドファイルの先頭に追加する。

## Goals / Non-Goals

**Goals:**

- 6 コマンドに YAML frontmatter `tools` フィールドを追加し tools-mismatch 0 件にする
- co-issue SKILL.md を 120 行以下にリファクタリングし controller-bloat 0 件にする
- `loom check` / `loom validate` が引き続き PASS すること

**Non-Goals:**

- deep-validate ルール自体の変更
- frontmatter の tools 以外のフィールド追加
- コマンドの動作変更

## Decisions

1. **frontmatter 追加形式**: 既存の agents と同じ `---` 囲み + `tools: [...]` インライン配列形式を使用。コマンドにはまだ frontmatter がないため新規追加
2. **co-issue 削減方針**: Phase 説明の簡潔化・冗長な禁止事項のインライン化で 15+ 行削減。ロジック変更なし

## Risks / Trade-offs

- frontmatter 追加により各コマンドファイルが 3 行増加するが、deep-validate 準拠のために必要
- co-issue の行数削減は情報密度を上げるため可読性に若干影響するが、120 行制約遵守が優先
