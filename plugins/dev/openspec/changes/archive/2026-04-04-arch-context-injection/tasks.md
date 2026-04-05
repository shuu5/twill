## 1. co-issue SKILL.md 修正

- [x] 1.1 Phase 1 の冒頭に `architecture/` 存在チェックを追加
- [x] 1.2 存在時に `vision.md`・`domain/context-map.md`・`domain/glossary.md` を Read する指示を追加
- [x] 1.3 explore の prompt に `## Architecture Context` セクションを注入する指示を追記

## 2. issue-structure.md 修正

- [x] 2.1 Step 2.5 の `ctx/<name>` ラベル提案ロジックを確認
- [x] 2.2 単一マッチ時に `<!-- arch-ref-start -->` タグを生成する指示を追記
- [x] 2.3 複数マッチ時は主要 context のパスのみ、該当なし時はタグ非出力のルールを追記

## 3. merge-gate.md 修正

- [x] 3.1 動的レビュアー構築セクションに `architecture/` 存在チェック条件を追加
- [x] 3.2 存在時に `worker-architecture` を specialist リストへ追加する指示を追記

## 4. worker-architecture.md 修正

- [x] 4.1 既存の `plugin_path` モードの説明セクションを確認
- [x] 4.2 `pr_diff` 入力モードのセクションを追加（ADR・invariants・contracts の Read と検証）
- [x] 4.3 `architecture-violation` カテゴリを使用する出力例を追加

## 5. contracts/specialist-output-schema.md 修正

- [x] 5.1 `category` 定義に `architecture-violation` を追加

## 6. deps.yaml 修正

- [x] 6.1 `merge-gate.calls` に `worker-architecture` を追加

## 7. 検証

- [x] 7.1 `loom check` で deps.yaml 整合性を確認
- [x] 7.2 `loom update-readme` を実行
