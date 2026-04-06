## Why

specialist 型コンポーネントに model フィールドの宣言が必須化されたが、twl CLI は validate / deep-validate / audit のいずれでも model フィールドの有無をチェックしていない。意図しない高コスト model 使用を防ぐために、機械的な検証が必要。

## What Changes

- deep-validate に model 宣言チェックルール `model-required` を追加
- specialist で model 未宣言 → WARNING
- specialist で未知の model 値 → INFO（タイポ検出）
- specialist で opus 宣言 → WARNING（設計判断: specialist に opus は使わない）
- audit に "Model Declaration" セクションを追加
- ALLOWED_MODELS 定数を twl-engine.py に定義

## Capabilities

### New Capabilities

- deep-validate が specialist の model フィールドを検証する
- audit が全 specialist の model 宣言状況を一覧表示する

### Modified Capabilities

- deep-validate: 新ルール `model-required` を追加
- audit: Section 6 "Model Declaration" を追加

## Impact

- twl-engine.py: ALLOWED_MODELS 定数追加、deep-validate ロジック拡張、audit セクション追加
- テスト: 新規テストケース追加（model 未宣言、未知値、opus 宣言）
- specialist 以外の型は影響なし
