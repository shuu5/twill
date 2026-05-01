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

## Alternatives

1. **ハードコード維持（現状案）**: `architect-completeness-check.md` の Step 1 テーブルを書き換えず、TI-1 実装時にコマンド自体を修正する。変更コストは低いが、TI-1 実装毎に `architect-completeness-check.md` への変更が必要となり、仕様と実装が分散したまま残る。
2. **専用設定ファイル分離案**: `severity-config.yaml` のような独立した設定ファイルを導入し、Severity を外部化する。柔軟性は高いが、新規ファイルの追加と管理コストが発生し、既存 `ref-architecture-spec.md` との二重管理になる。
3. **採用案（ref-architecture-spec.md への Severity 列追加）**: SSOT を既存の参照ファイル（`ref-architecture-spec.md`）に集約する。新規ファイル追加不要、既存 Read 操作の延長で実現可能、TI-1 対応もテーブル変更のみで済む。

## Consequences

- **良い面**: `ref-architecture-spec.md` のテーブル変更のみで Severity を切替可能になる（TI-1 が選択肢として活用可）。`architect-completeness-check.md` の保守コストが低減し、仕様と実装の乖離が防止される。
- **悪い面**: `architect-completeness-check` 実行時に `ref-architecture-spec.md` の Read が毎回必須となる（コマンド呼び出し 1 回あたり Read 1 回の追加）。`ref-architecture-spec.md` が不在の場合は Severity 情報が取得できないため、フォールバック挙動（デフォルト WARNING）を実装側で考慮する必要がある。また、`ref-architecture-spec.md` の Severity 列が意図せず変更された場合（WARNING → RECOMMENDED）、既存プロジェクトのチェックが警告なく降格するリスクがある。
- **TI-1 接続**: TI-1（`--lightweight` フラグ）の実装時は、`ref-architecture-spec.md` の Severity 列を `RECOMMENDED` に変更するだけで軽量チェックモードが実現可能となる。
