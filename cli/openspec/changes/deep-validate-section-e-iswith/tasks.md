## 1. コード修正

- [x] 1.1 `loom-engine.py` line 2920: `path = plugin_root / path_str` の直後に `_is_within_root(path, plugin_root)` チェックを追加し、False なら `continue`

## 2. テスト追加

- [x] 2.1 パストラバーサル path（`../../etc/passwd`）を含む specialist コンポーネントで `deep_validate()` がスキップすることを検証するテストを追加
- [x] 2.2 既存テスト全件 PASS を確認（`pytest tests/`）
