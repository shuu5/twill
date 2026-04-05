## Why

`deep_validate()` section E で `output_schema` の空文字列チェック（`!= ""`）により、`output_schema: ""` と明示宣言されたケースが未宣言（`None`）と同一扱いになる。空文字列は invalid value として警告すべき。

## What Changes

- `twl-engine.py` line 2913 付近: `output_schema` の空文字列を独立した invalid value として検出・警告
- 既存の `!= ""` ガードを削除し、空文字列専用の警告パスを追加

## Capabilities

### New Capabilities

- `output_schema: ""` が明示的に invalid value として警告される

### Modified Capabilities

- `output_schema` の検証ロジック: `None`（未宣言）と `""`（空文字列）を区別して処理

## Impact

- `twl-engine.py`: `deep_validate()` section E の output_schema 検証ブロック（line 2910-2914 付近）
- 既存テスト: 動作変更なし（`custom` / `None` のパスは不変）
- 新規テスト: 空文字列ケースの警告検証が必要
