## Why

`co-architect` は `vision.md` で「Non-implementation controller」に分類されているが、実際には `architecture/` にファイルを直接 Write し main worktree にコミットしている。この分類と実態の矛盾を ADR-019 として記録し、新カテゴリ「Spec Implementation」を導入することで整合性を回復する。

## What Changes

- `plugins/twl/architecture/decisions/ADR-019-spec-implementation-category.md`（新規）を作成し、Decision と Consequences を記録する
- `plugins/twl/architecture/vision.md` の controller カテゴリテーブルに「Spec Implementation」行を追加する（Non-implementation から co-architect を移動）
- `plugins/twl/architecture/domain/glossary.md` の MUST 用語リストに「Spec Implementation」を追加する

## Capabilities

### New Capabilities

- ADR-019 による「Spec Implementation」カテゴリの公式定義（Architecture spec 変更・PR 作成を担う controller カテゴリ）

### Modified Capabilities

- `vision.md` controller カテゴリテーブルが 5 行 → 6 行に拡大（co-architect が Non-implementation から Spec Implementation に再分類）
- `glossary.md` MUST 用語に「Spec Implementation」が追加される

## Impact

- `plugins/twl/architecture/decisions/ADR-019-spec-implementation-category.md`（新規）
- `plugins/twl/architecture/vision.md`（カテゴリテーブル更新）
- `plugins/twl/architecture/domain/glossary.md`（用語追加）
- SKILL.md・deps.yaml への変更なし（#4, #5 で対応）
