## ADDED Requirements

### Requirement: ADR-019 ファイルの作成

ADR-019 は `plugins/twl/architecture/decisions/ADR-019-spec-implementation-category.md` に作成されなければならない（SHALL）。
ADR は **Status**: Accepted、**Date**: 2026-04-13、**Issue**: #557 のヘッダーを持ち、Context/Decision/Consequences/Alternatives の各セクションを含まなければならない（SHALL）。

#### Scenario: ADR-019 ファイルが正しい場所に作成される
- **WHEN** issue-557 の実装タスクが完了した後
- **THEN** `plugins/twl/architecture/decisions/ADR-019-spec-implementation-category.md` が存在し、`Status: Accepted` と `Issue: #557` を含む

#### Scenario: Alternatives セクションが記録される
- **WHEN** ADR-019 を参照したとき
- **THEN** 「既存 Implementation に統合」と「ADR 例外として対応」の 2 つの代替案がそれぞれ選択しなかった理由とともに記載されている

### Requirement: vision.md controller カテゴリテーブルの更新

`plugins/twl/architecture/vision.md` の「Controller 操作カテゴリ」テーブルは「Spec Implementation」行を含まなければならない（SHALL）。
`co-architect` は Non-implementation から Spec Implementation カテゴリに移動されなければならない（MUST）。
Non-implementation の「該当 Controller」列は `co-issue, co-project` のみを含まなければならない（SHALL）。

#### Scenario: Spec Implementation 行が追加される
- **WHEN** 更新後の vision.md を参照したとき
- **THEN** カテゴリテーブルに `Spec Implementation | Architecture spec 変更・PR 作成 | co-architect` の行が存在する

#### Scenario: Non-implementation から co-architect が除外される
- **WHEN** 更新後の vision.md を参照したとき
- **THEN** Non-implementation の「該当 Controller」列には `co-architect` が含まれず `co-issue, co-project` のみである

#### Scenario: 説明文が更新される
- **WHEN** 更新後の vision.md の Spec Implementation 行直下を参照したとき
- **THEN** 「Non-implementation controller と Spec Implementation controller は co-autopilot を spawn しない。」の文が存在する

### Requirement: glossary.md MUST 用語への追加

`plugins/twl/architecture/domain/glossary.md` の MUST 用語テーブルに「Spec Implementation」エントリが追加されなければならない（SHALL）。
エントリは用語・定義・Context 列を持ち、定義には ADR-019 への参照を含まなければならない（MUST）。

#### Scenario: Spec Implementation 用語が MUST テーブルに存在する
- **WHEN** 更新後の glossary.md を参照したとき
- **THEN** MUST 用語テーブルに「Spec Implementation」の行が存在し、定義には「ADR-019」への参照が含まれる

#### Scenario: 用語照合で検出可能になる
- **WHEN** co-issue Step 1.5 が Issue body の「Spec Implementation」という用語を照合したとき
- **THEN** glossary.md の完全一致で「Spec Implementation」が定義済み用語として検出される
