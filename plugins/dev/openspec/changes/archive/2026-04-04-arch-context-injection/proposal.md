## Why

`architecture/` ディレクトリには 9 つの不変条件・6 Bounded Context・5 ADR・2 契約が定義されているが、co-issue・merge-gate・specialist の各ワークフローで機械的に参照されていない。その結果、Bounded Context と不整合な Issue が作成され、ADR/invariant を無視したコードがマージされるリスクがある。

## What Changes

- `skills/co-issue/SKILL.md`: Phase 1 explore 呼び出し時に `vision.md` + `domain/context-map.md` + `domain/glossary.md` を architecture context として注入
- `commands/issue-structure.md`: Step 2.5 に `<!-- arch-ref-start -->` タグ自動生成ロジックを追記（ctx/* ラベルとの連動）
- `commands/merge-gate.md`: `architecture/` 存在時に `worker-architecture` を動的レビュアーリストへ自動追加
- `agents/worker-architecture.md`: `pr_diff` 入力モードを追加（ADR・invariant・contract との整合性検証）
- `contracts/specialist-output-schema.md`: `architecture-violation` カテゴリを追加
- `deps.yaml`: `merge-gate.calls` に `worker-architecture` を追加

## Capabilities

### New Capabilities

- **architecture-aware Issue 作成**: co-issue が architecture context を inject して explore を実行。Bounded Context と整合した Issue 分解が可能になる
- **arch-ref タグ自動生成**: issue-structure が `ctx/*` ラベルと同時に `<!-- arch-ref-start -->` タグを出力し、downstream の workflow-setup で architecture context が引き継がれる
- **PR diff での architecture 検証**: worker-architecture が ADR・invariant・contract を参照し、PR diff との整合性を機械的に検証する

### Modified Capabilities

- **merge-gate 動的レビュアー構築**: `architecture/` ディレクトリ存在時、worker-architecture が標準 specialist として自動追加される（architecture 非存在プロジェクトへの影響ゼロ）
- **specialist-output-schema**: `category` 定義に `architecture-violation` を追加し、architecture 違反を機械的フィルタリング可能にする

## Impact

- 対象ファイル: `skills/co-issue/SKILL.md`, `commands/issue-structure.md`, `commands/merge-gate.md`, `agents/worker-architecture.md`, `contracts/specialist-output-schema.md`, `deps.yaml`
- architecture/ が存在しないプロジェクトへの影響: ゼロ（全変更が条件分岐内）
- downstream への影響: workflow-setup の arch-ref ステップが機能するようになる（既存ロジックの活性化）
