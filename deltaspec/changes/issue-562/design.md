## Context

`co-architect` の責務再定義（#560）により `architect-decompose` と `architect-issue-create` が呼び出しチェーンから除外され、orphan コンポーネントとなった。TWiLL の deps.yaml は SSOT（Single Source of Truth）として依存グラフを管理しており、orphan エントリは `twl check` の違反として検出される。これらのコンポーネントの機能は `co-issue` Phase 1（explore + ARCH_CONTEXT 注入）と Phase 3/4（specialist review + workflow-issue-create）で代替可能であり、重複実装の削除が適切な対応となる。

## Goals / Non-Goals

**Goals:**
- `architect-decompose` と `architect-issue-create` を deps.yaml から削除する
- 対応するコマンドファイルを削除する
- `twl check` が 0 violations、0 orphans で通ることを確認する

**Non-Goals:**
- `co-issue` SKILL.md への機能追加（別 Issue で対応）
- `ref-project-model.md` 等の docs 内参照の更新（archive/reference 扱い）
- `ref-gh-read-policy.md` の参照更新（軽微なコメント参照のため対象外）

## Decisions

1. **廃止のみ、移植なし**: `co-issue` が既に architecture spec ベースの Issue 分解機能を提供しているため、`architect-decompose` の 6 項目整合性チェックを co-issue へ移植する必要はない（co-issue Phase 3 の specialist review で代替可能）
2. **docs 参照は更新しない**: `ref-project-model.md`（110, 122, 162, 170, 178 行）と `ref-gh-read-policy.md`（42 行）の参照は archive/documentation 目的の記述であり、機能に影響しないため変更対象外とする
3. **component-mapping.md は変更しない**: `architecture/archive/migration/` 配下は歴史的記録であり変更対象外

## Risks / Trade-offs

- **リスク低**: deps.yaml からのエントリ削除はコマンドファイル削除と同時に行うため、参照整合性が保たれる
- **トレードオフ**: docs 内の参照は古い情報として残るが、読者への混乱リスクは低い（archive ディレクトリ内かつ機能的参照でない）
- **検証**: `twl check` を廃止後に実行して violations/orphans が 0 であることを確認する
