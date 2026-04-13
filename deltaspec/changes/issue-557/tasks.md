## 1. ADR-019 作成

- [x] 1.1 `plugins/twl/architecture/decisions/ADR-019-spec-implementation-category.md` を新規作成する（Status: Accepted, Date: 2026-04-13, Issue: #557）
- [x] 1.2 Context セクションを記述する（co-architect の Non-implementation 分類との矛盾）
- [x] 1.3 Decision セクションを記述する（Spec Implementation カテゴリの導入）
- [x] 1.4 Consequences セクションを記述する（vision.md テーブルの変更、glossary.md 用語追加）
- [x] 1.5 Alternatives セクションを記述する（「既存 Implementation に統合」「ADR 例外として対応」を選択しなかった理由付きで記録）

## 2. vision.md 更新

- [x] 2.1 `plugins/twl/architecture/vision.md` を読み込み、「Controller 操作カテゴリ」テーブルを確認する
- [x] 2.2 テーブルに「Spec Implementation | Architecture spec 変更・PR 作成 | co-architect」行を追加する（Implementation と Non-implementation の間）
- [x] 2.3 Non-implementation 行の「該当 Controller」から `co-architect` を除去し `co-issue, co-project` のみにする
- [x] 2.4 テーブル直下の説明文を「Non-implementation controller と Spec Implementation controller は co-autopilot を spawn しない。」に更新する

## 3. glossary.md 更新

- [x] 3.1 `plugins/twl/architecture/domain/glossary.md` の MUST 用語テーブルに「Spec Implementation」エントリを追加する（定義に ADR-019 参照を含む）
