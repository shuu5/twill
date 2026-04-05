## 1. output_schema 検証ロジック修正

- [x] 1.1 `twl-engine.py` line 2913 の `output_schema is not None and output_schema != ''` 条件を再構成し、空文字列を独立した invalid value として検出する
- [x] 1.2 空文字列専用の警告メッセージ `empty output_schema value (expected 'custom' or omit)` を追加

## 2. テスト

- [x] 2.1 `output_schema: ""` で空文字列警告が出力されるテストケースを追加
- [x] 2.2 既存テスト（`custom` / `None` / その他無効値）が PASS を維持することを確認
