# ADR-032: architect-completeness-check に Severity 列を導入し動的化する

## Status

accepted

## Context

`architect-completeness-check` コマンドの Step 1 必須テーブルは、不在時のレポートレベル（`WARNING` / `INFO`）がハードコードされていた。TI-1（`--lightweight` フラグ導入）の設計では、一部の必須チェックを `RECOMMENDED`（不在 = INFO）に段階的に降格させることで、軽量チェックモードを実現する予定がある。このハードコード構造のままでは、TI-1 の実装時に `architect-completeness-check.md` 自体を書き換える必要があり、変更コストと回帰リスクが高い。

また、`ref-architecture-spec.md` がアーキテクチャ仕様の SSOT として機能しているにもかかわらず、`architect-completeness-check.md` の Step 1 テーブルが独立した定義を持つ二重管理状態であった（lightweight noise）。

## Decision

`ref-architecture-spec.md` の `## 必須ファイル` テーブルに `Severity` 列（値域: `WARNING` または `RECOMMENDED`）を追加し、`architect-completeness-check.md` の Step 1 がこのテーブルを Read して Severity を動的に参照する設計に変更する。

- `Severity=WARNING` のパスが不在 → `[WARNING]` で報告
- `Severity=RECOMMENDED` のパスが不在 → `[INFO]` で報告（WARNING より低い）
- `ref-architecture-spec.md` が Severity の SSOT となる（architect-completeness-check.md へのハードコード禁止）

既定状態では現行 5 必須ファイル（`vision.md`, `domain/model.md`, `domain/glossary.md`, `domain/contexts/*.md`, `phases/*.md`）が `WARNING`、任意ファイル（`decisions/*.md`, `contracts/*.md`）が `RECOMMENDED` に設定し、既存の動作を regression なく維持する。

## Consequences

- **良い面**: `ref-architecture-spec.md` のテーブル変更のみで Severity を切替可能になる（TI-1 が選択肢として活用可）。`architect-completeness-check.md` の保守コストが低減し、仕様と実装の乖離が防止される。
- **悪い面**: `architect-completeness-check` 実行時に `ref-architecture-spec.md` の Read が必須となる（軽微なオーバーヘッド）。
- **TI-1 接続**: TI-1（`--lightweight` フラグ）の実装時は、`ref-architecture-spec.md` の Severity 列を `RECOMMENDED` に変更するだけで軽量チェックモードが実現可能となる。
